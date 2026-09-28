import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api_log.dart';
import '../../core/app_constants.dart';
import '../../domain/entities/driver.dart';
import '../../domain/entities/driver_duty.dart';
import '../../domain/entities/fee_due.dart';
import '../../domain/entities/gps_point.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/entities/payment_record.dart';
import '../../domain/entities/student.dart';
import '../../domain/entities/transport_log.dart';
import '../../domain/entities/vehicle.dart';

// Generous enough for the backend's queries against the remote database, which
// can be slow. A too-short timeout used to trigger a mid-session backend
// failover that logged users out (see _withBaseUrl).
const _localBackendTimeout = Duration(seconds: 20);

/// Thrown whenever the backend rejects a request with 401 (missing, invalid,
/// or expired token). The session token is cleared as soon as this is thrown
/// so the next request doesn't repeat the same failure; callers should send
/// the user back to the login screen.
class SessionExpiredException implements Exception {
  const SessionExpiredException();
  @override
  String toString() => 'Your session has expired. Please log in again.';
}

class CampusRemoteDataSource {
  String? _sessionToken;
  String? _cachedBaseUrl;

  void setSessionToken(String? token) {
    if (token == null || token.isEmpty) {
      sessionLog('token CLEARED (was ${describeToken(_sessionToken)})');
    } else {
      sessionLog('token set -> ${describeToken(token)}');
    }
    _sessionToken = token;
  }

  /// Always performs a fresh health-check across the configured base URLs.
  Future<String> resolveApiBaseUrl() async {
    Object? lastError;
    final candidates = apiBaseUrls.where((url) => url.isNotEmpty).toList();
    apiLog('resolving base URL from ${candidates.length} candidate(s)');
    for (final baseUrl in candidates) {
      try {
        final response = await http
            .get(Uri.parse('$baseUrl/health'))
            .timeout(_localBackendTimeout);
        if (response.statusCode == 200) {
          apiLog('using backend: $baseUrl');
          return baseUrl;
        }
        apiLog('candidate $baseUrl -> health ${response.statusCode}, skipping');
        lastError = Exception(
          '$baseUrl/health returned ${response.statusCode}',
        );
      } catch (error) {
        apiLog('candidate $baseUrl -> unreachable: $error');
        lastError = error;
      }
    }
    throw Exception('No API host responded. Last error: $lastError');
  }

  /// Resolves the base URL once per session (cached) instead of health-checking
  /// before every single request. If a request against the cached URL fails,
  /// the cache is dropped and the URL is re-resolved once before giving up.
  Future<T> _withBaseUrl<T>(Future<T> Function(String baseUrl) action) async {
    final baseUrl = _cachedBaseUrl ??= await resolveApiBaseUrl();
    try {
      return await action(baseUrl);
    } on SessionExpiredException {
      rethrow;
    } catch (error) {
      // Retry once against the SAME backend for a transient blip. We must never
      // fail over to a *different* backend mid-session: a session token minted
      // on one backend is rejected (401) by another, forcing a spurious logout.
      // The initial resolveApiBaseUrl() already picked a reachable backend.
      apiLog('retrying once against $baseUrl after: $error');
      return action(baseUrl);
    }
  }

  Map<String, String> _authHeaders(String path) {
    final token = _sessionToken;
    if (token == null) {
      // Not the root cause on its own — it means something *earlier* already
      // cleared the token (see the "AUTH 401" line above this one in the log),
      // or the token was never handed to this data source instance.
      apiLog('BLOCKED $path — no session token in memory');
      throw const SessionExpiredException();
    }
    return {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
  }

  void _throwIfUnauthorized(http.Response response, String path) {
    if (response.statusCode == 401) {
      // The body distinguishes the two very different causes:
      //   "Login is required"             -> requireScopedSession rejected the token
      //   "Super admin login is required" -> the path matched NO route in the
      //      parent/driver router and fell through to requireSuperAdmin, i.e.
      //      the deployed backend does not have this endpoint.
      //
      // Only the first means the session is over. The second is a missing or
      // admin-only route: the token is still valid, and logging out would just
      // repeat the same failure on the next login.
      if (response.body.contains('Super admin login is required')) {
        apiLog(
          'ROUTE 401 on $path -> not served to this session, keeping token '
          '| body: ${shortBody(response.body)}',
        );
        throw Exception('This feature is not available on the server yet.');
      }
      apiLog(
        'AUTH 401 on $path -> clearing token ${describeToken(_sessionToken)} '
        '| body: ${shortBody(response.body)}',
      );
      _sessionToken = null;
      throw const SessionExpiredException();
    }
  }

  /// Single choke point for every backend call, so each request's method, path,
  /// status and duration land in the log in one consistent format.
  Future<http.Response> _send(
    String method,
    String baseUrl,
    String path, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse('$baseUrl$path');
    try {
      final request = method == 'POST'
          ? http.post(uri, headers: headers, body: body)
          : http.get(uri, headers: headers);
      final response = await request.timeout(_localBackendTimeout);
      apiLog('$method $path -> ${response.statusCode} (${stopwatch.elapsedMilliseconds}ms)');
      return response;
    } catch (error) {
      apiLog('$method $path -> FAILED after ${stopwatch.elapsedMilliseconds}ms: $error');
      rethrow;
    }
  }

  dynamic _decodeOrThrow(http.Response response) {
    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? message;
      if (decoded is Map<String, dynamic>) {
        final errorField = decoded['error'];
        if (errorField is Map<String, dynamic>) {
          message = errorField['message']?.toString();
        }
      }
      throw Exception(message ?? 'Request failed with status ${response.statusCode}');
    }
    return decoded;
  }

  Map<String, dynamic> _decodeMapOrThrow(http.Response response) {
    return _decodeOrThrow(response) as Map<String, dynamic>;
  }

  // ---- Public (unauthenticated) OTP endpoints ----

  Future<String?> requestParentOtp(String phone) =>
      _requestOtp('/mobile-auth/parent/request-otp', phone);

  Future<String?> requestDriverOtp(String phone) =>
      _requestOtp('/mobile-auth/driver/request-otp', phone);

  Future<String> verifyParentOtp(String phone, String otp) =>
      _verifyOtp('/mobile-auth/parent/verify-otp', phone, otp);

  Future<String> verifyDriverOtp(String phone, String otp) =>
      _verifyOtp('/mobile-auth/driver/verify-otp', phone, otp);

  Future<String?> _requestOtp(String path, String phone) {
    return _withBaseUrl((baseUrl) async {
      apiLog('requesting OTP for ${maskPhone(phone)}');
      final response = await _send(
        'POST',
        baseUrl,
        path,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone}),
      );
      final result = _decodeMapOrThrow(response);
      // Whether the backend returns devOtp tells us if OTP_DEMO_MODE is on.
      apiLog('OTP requested; devOtp ${result.containsKey('devOtp') ? 'returned' : 'NOT returned'}');
      return result['devOtp']?.toString();
    });
  }

  Future<String> _verifyOtp(String path, String phone, String otp) {
    return _withBaseUrl((baseUrl) async {
      final response = await _send(
        'POST',
        baseUrl,
        path,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'otp': otp}),
      );
      final result = _decodeMapOrThrow(response);
      final token = result['token']?.toString() ?? '';
      if (token.isEmpty) throw Exception('Login did not return a session token.');
      // The phone the *backend* put in the token (E.164) vs the one the app
      // sent (bare 10 digits) — a mismatch here explains empty parent/driver
      // data even when auth itself succeeds.
      sessionLog(
        'login OK: sent ${maskPhone(phone)}, token says ${maskPhone(result['phone']?.toString())}',
      );
      return token;
    });
  }

  // ---- Scoped parent endpoints ----

  Future<List<Student>> fetchParentChildren() async {
    final rows = await _authorizedGetList('/parent/children');
    return rows.map(_studentFromJson).toList();
  }

  Future<List<Vehicle>> fetchParentVehicles() async {
    final rows = await _authorizedGetList('/parent/vehicles');
    return rows.map(_vehicleFromJson).toList();
  }

  Future<List<FeeDue>> fetchParentFeeDues({String? month}) async {
    final query = (month == null || month.isEmpty) ? '' : '?month=$month';
    final rows = await _authorizedGetList('/parent/fee-dues$query');
    return rows.map(_feeDueFromJson).toList();
  }

  Future<List<PaymentRecord>> fetchParentPayments() async {
    final rows = await _authorizedGetList('/parent/payments');
    return rows.map(_paymentRecordFromJson).toList();
  }

  Future<List<TransportLog>> fetchParentTransportLogs({int? studentId}) async {
    final query = studentId == null ? '' : '?studentId=$studentId';
    final rows = await _authorizedGetList('/parent/transport-logs$query');
    return rows.map(_transportLogFromJson).toList();
  }

  Future<List<NotificationItem>> fetchParentNotifications() async {
    final rows = await _authorizedGetList('/parent/notifications');
    return rows.map(_notificationFromJson).toList();
  }

  Future<void> markParentNotificationsRead() =>
      _authorizedPost('/parent/notifications/read', const {});

  // ---- Push-token registration (parent or driver) ----

  Future<void> registerParentDeviceToken(String token, String platform) =>
      _authorizedPost('/parent/device-token', {'token': token, 'platform': platform});

  Future<void> registerDriverDeviceToken(String token, String platform) =>
      _authorizedPost('/driver/device-token', {'token': token, 'platform': platform});

  // ---- Scoped driver endpoints ----

  Future<Driver> fetchDriverProfile() async {
    final row = await _authorizedGetMap('/driver/me');
    return _driverFromJson(row);
  }

  Future<({Vehicle? vehicle, List<Student> students})> fetchDriverRoster() async {
    final row = await _authorizedGetMap('/driver/roster');
    final vehicleJson = row['vehicle'] as Map<String, dynamic>?;
    final studentsJson = (row['students'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>();
    return (
      vehicle: vehicleJson == null ? null : _vehicleFromJson(vehicleJson),
      students: studentsJson.map(_studentFromJson).toList(),
    );
  }

  Future<DriverDuty> fetchDriverDuty() async {
    return _driverDutyFromJson(await _authorizedGetMap('/driver/duty'));
  }

  Future<DriverDuty> recordDriverDuty({
    required String action,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    final row = await _authorizedPostMap('/driver/duty', {
      'action': action,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
    });
    return _driverDutyFromJson(row);
  }

  Future<void> createDriverTransportLog({
    required int studentId,
    required String action,
    required DateTime recordedAt,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) {
    return _authorizedPost('/driver/transport-logs', {
      'studentId': studentId,
      'action': action,
      // UTC with a Z. A local DateTime serializes with no offset, which the
      // server reads as UTC. (The server now stamps its own clock anyway.)
      'recordedAt': recordedAt.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
    });
  }

  // ---- Vehicle positions ----
  //
  // Read from our own backend, never from the GPS provider. The provider sends
  // no CORS headers, its credential must not ship inside the app, and it allows
  // only one call a minute across the whole account -- so every phone calling it
  // directly would have starved every other phone. The backend polls once and
  // stores what it sees; these are plain database reads.

  /// Positions for the bus this driver is assigned to, and no other.
  ///
  /// The fleet-wide /gps/vehicles endpoint is super-admin only. Calling it
  /// with a driver token got a 401, which cleared the session and sent the
  /// driver straight back to the login screen.
  Future<List<GpsPoint>> fetchDriverGpsPoints() async {
    final rows = await _authorizedGetList('/driver/vehicle-positions');
    return rows.map(_gpsFromJson).toList();
  }

  /// Where this driver's bus has been since [from], oldest first -- the route
  /// line on the driver's map. Scoped server-side to their own bus.
  Future<List<GpsPoint>> fetchDriverRouteTrail({required DateTime from}) =>
      _fetchRouteTrail('/driver/vehicle-positions/history', from: from);

  /// Where one child's bus has been since [from], oldest first -- the route
  /// line on the parent's map. The backend refuses a child not linked to
  /// this parent.
  Future<List<GpsPoint>> fetchParentRouteTrail({
    required int studentId,
    required DateTime from,
  }) => _fetchRouteTrail(
    '/parent/vehicle-positions/history',
    from: from,
    studentId: studentId,
  );

  Future<List<GpsPoint>> _fetchRouteTrail(
    String path, {
    required DateTime from,
    int? studentId,
  }) async {
    final query = Uri(
      queryParameters: {
        if (studentId != null) 'studentId': '$studentId',
        'from': from.toUtc().toIso8601String(),
        // A full day is at most ~1,000 stored positions (one per 90 s poll).
        'limit': '2000',
      },
    ).query;
    final payload = await _authorizedGetMap('$path?$query');
    final rows = payload['positions'];
    if (rows is! List) return const [];
    return rows.whereType<Map<String, dynamic>>().map(_gpsFromJson).toList();
  }

  /// Positions for the bus this parent's own children ride, and no other.
  ///
  /// Scoped server-side from the session phone. The fleet-wide /gps/vehicles
  /// endpoint would hand a parent every bus in the school, including those
  /// carrying other people's children.
  Future<List<GpsPoint>> fetchParentGpsPoints() async {
    final rows = await _authorizedGetList('/parent/vehicle-positions');
    return rows.map(_gpsFromJson).toList();
  }

  /// One bus, by fleet code (BUS-01) or registration number.
  ///
  /// Sent directly rather than through _authorizedGetMap so a 404 can be read
  /// as "no position reported yet" -- an absent bus, not an error worth showing
  /// a parent.
  Future<GpsPoint?> fetchGpsPointForVehicle(String vehicle) {
    final path = '/gps/vehicles/${Uri.encodeComponent(vehicle)}';
    return _withBaseUrl((baseUrl) async {
      final response = await _send('GET', baseUrl, path, headers: _authHeaders(path));
      _throwIfUnauthorized(response, path);
      if (response.statusCode == 404) return null;
      return _gpsFromJson(_decodeMapOrThrow(response));
    });
  }

  // ---- Shared authorized request helpers ----

  Future<List<Map<String, dynamic>>> _authorizedGetList(String path) {
    return _withBaseUrl((baseUrl) async {
      final response = await _send('GET', baseUrl, path, headers: _authHeaders(path));
      _throwIfUnauthorized(response, path);
      final decoded = _decodeOrThrow(response);
      return (decoded as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().toList();
    });
  }

  Future<Map<String, dynamic>> _authorizedGetMap(String path) {
    return _withBaseUrl((baseUrl) async {
      final response = await _send('GET', baseUrl, path, headers: _authHeaders(path));
      _throwIfUnauthorized(response, path);
      return _decodeMapOrThrow(response);
    });
  }

  Future<void> _authorizedPost(String path, Map<String, dynamic> payload) {
    return _withBaseUrl((baseUrl) async {
      final response = await _send(
        'POST',
        baseUrl,
        path,
        headers: _authHeaders(path),
        body: jsonEncode(payload),
      );
      _throwIfUnauthorized(response, path);
      _decodeOrThrow(response);
    });
  }

  Future<Map<String, dynamic>> _authorizedPostMap(
    String path,
    Map<String, dynamic> payload,
  ) {
    return _withBaseUrl((baseUrl) async {
      final response = await _send(
        'POST',
        baseUrl,
        path,
        headers: _authHeaders(path),
        body: jsonEncode(payload),
      );
      _throwIfUnauthorized(response, path);
      return _decodeMapOrThrow(response);
    });
  }
}

/// Server timestamps are UTC ISO strings ("...Z"). Parsed as-is they stay UTC,
/// so `.hour` and day comparisons would read UTC and show IST times 5:30 off;
/// converting here means every screen works in the phone's own time.
DateTime? _localTime(Object? value) =>
    value == null ? null : DateTime.tryParse('$value')?.toLocal();

DriverDuty _driverDutyFromJson(Map<String, dynamic> json) {
  DutyEvent? event(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final time = _localTime(value['recordedAt']);
    if (time == null) return null;
    return DutyEvent(
      time: time,
      latitude: _doubleValue(value['latitude']),
      longitude: _doubleValue(value['longitude']),
      accuracy: _doubleValue(value['accuracy']),
    );
  }

  return DriverDuty(
    onDuty: json['onDuty'] == true,
    checkIn: event(json['checkIn']),
    checkOut: event(json['checkOut']),
  );
}

Vehicle _vehicleFromJson(Map<String, dynamic> json) {
  return Vehicle(
    id: '${json['id'] ?? json['vehicle_id'] ?? json['vehicleCode'] ?? json['vehicle_code'] ?? ''}',
    plate:
        '${json['plate'] ?? json['registration_number'] ?? json['vehicleNo'] ?? ''}',
    driver: '${json['driver'] ?? json['driver_name'] ?? 'Unassigned'}',
    route: '${json['route'] ?? '-'}',
    speed: json['speed'] is num ? json['speed'] as num : 0,
    status: '${json['status'] ?? 'Offline'}',
    students: json['students'] is num ? (json['students'] as num).toInt() : 0,
    x: json['x'] is num ? json['x'] as num : 50,
    y: json['y'] is num ? json['y'] as num : 50,
  );
}

Student _studentFromJson(Map<String, dynamic> json) {
  return Student(
    id: _intValue(json['studentId'] ?? json['id']),
    name: '${json['name'] ?? json['full_name'] ?? ''}',
    regNo: '${json['regNo'] ?? json['registration_number'] ?? ''}',
    className:
        '${json['class'] ?? json['className'] ?? json['class_name'] ?? ''}',
    phone: onlyDigits('${json['phone'] ?? ''}'),
    secondaryPhone: onlyDigits(
      '${json['secondaryPhone'] ?? json['secondary_phone'] ?? ''}',
    ),
    vehicle:
        '${json['vehicle'] ?? json['vehicle_code'] ?? json['vehicleId'] ?? 'Unassigned'}',
    area: '${json['area'] ?? json['address'] ?? ''}',
    route: '${json['routeName'] ?? json['route'] ?? json['routeCode'] ?? '-'}',
    monthlyDue: json['monthlyDue'] is num
        ? json['monthlyDue'] as num
        : num.tryParse('${json['monthlyDue'] ?? 0}') ?? 0,
    branch: '${json['branch'] ?? ''}',
  );
}

Driver _driverFromJson(Map<String, dynamic> json) {
  return Driver(
    id: _intValue(json['driverId'] ?? json['id']),
    name: '${json['name'] ?? json['full_name'] ?? ''}',
    phone: onlyDigits('${json['phone'] ?? ''}'),
    vehicle: '${json['vehicle'] ?? json['vehicle_code'] ?? 'Unassigned'}',
    route: '${json['route'] ?? '-'}',
  );
}

GpsPoint _gpsFromJson(Map<String, dynamic> json) {
  // reportedAt is the provider's own clock, forwarded by the backend as ISO.
  final reported = _localTime(json['reportedAt']);
  return GpsPoint(
    // Prefer the fleet code the office knows the bus by, falling back to the
    // registration number for a vehicle the school has no record of.
    vehicleNo: '${json['vehicleCode'] ?? ''}'.isNotEmpty
        ? '${json['vehicleCode']}'
        : '${json['vehicleNo'] ?? ''}',
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    speed: json['speed'] is num ? json['speed'] as num : 0,
    ignition: json['ignition'] == true,
    odometer: json['odometer'] is num ? json['odometer'] as num : 0,
    timestamp: reported ?? DateTime.now(),
    alias: json['route']?.toString(),
    imei: json['imei']?.toString(),
  );
}

TransportLog _transportLogFromJson(Map<String, dynamic> json) {
  return TransportLog(
    id: _intValue(json['id']),
    studentId: _intValue(json['studentId'] ?? json['student_id']),
    action: '${json['action'] ?? ''}',
    recordedAt:
        _localTime(json['recordedAt'] ?? json['recorded_at']) ?? DateTime.now(),
    latitude: _doubleValue(json['latitude']),
    longitude: _doubleValue(json['longitude']),
    accuracy: _doubleValue(json['accuracy']),
  );
}

NotificationItem _notificationFromJson(Map<String, dynamic> json) {
  return NotificationItem(
    id: _intValue(json['id']),
    type: '${json['type'] ?? ''}',
    title: '${json['title'] ?? ''}',
    body: '${json['body'] ?? ''}',
    read: json['read'] == true,
    createdAt:
        _localTime(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
    studentId: json['studentId'] == null && json['student_id'] == null
        ? null
        : _intValue(json['studentId'] ?? json['student_id']),
  );
}

FeeDue _feeDueFromJson(Map<String, dynamic> json) {
  return FeeDue(
    id: _intValue(json['dueId'] ?? json['id']),
    studentId: _intValue(json['studentId'] ?? json['student_id']),
    student: '${json['student'] ?? ''}',
    month: '${json['month'] ?? ''}',
    billed: _numValue(json['billed']),
    paidAmount: _numValue(json['paidAmount'] ?? json['paid_amount']),
    balance: _numValue(json['balance']),
    status: '${json['status'] ?? 'Pending'}',
  );
}

PaymentRecord _paymentRecordFromJson(Map<String, dynamic> json) {
  return PaymentRecord(
    id: '${json['receiptId'] ?? json['id'] ?? ''}',
    studentId: _intValue(json['studentId'] ?? json['student_id']),
    student: '${json['student'] ?? json['studentName'] ?? ''}',
    plan: '${json['plan'] ?? ''}',
    amount: _numValue(json['amount']),
    date:
        DateTime.tryParse('${json['date'] ?? json['paidOn']}') ??
        DateTime.now(),
    method: '${json['method'] ?? '-'}',
    status: '${json['status'] ?? ''}',
  );
}

int _intValue(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double _doubleValue(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

num _numValue(Object? value) =>
    value is num ? value : num.tryParse('$value') ?? 0;

String onlyDigits(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
}
