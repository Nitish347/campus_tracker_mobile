import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/datasources/campus_remote_data_source.dart';
import '../../../domain/entities/driver.dart';
import '../../../domain/entities/driver_duty.dart';
import '../../../domain/entities/gps_point.dart';
import '../../../domain/entities/student.dart';
import '../../../domain/entities/vehicle.dart';
import '../../../domain/repositories/campus_repository.dart';

abstract class DriverEvent {}

class DriverStarted extends DriverEvent {}

class DriverRefreshed extends DriverEvent {}

class DriverTabChanged extends DriverEvent {
  DriverTabChanged(this.index);
  final int index;
}

class DriverDutyCheckedIn extends DriverEvent {}

class DriverDutyCheckedOut extends DriverEvent {}

class DriverPicked extends DriverEvent {
  DriverPicked(this.studentId);
  final int studentId;
}

class DriverDropped extends DriverEvent {
  DriverDropped(this.studentId);
  final int studentId;
}

class DriverNoticeSent extends DriverEvent {
  DriverNoticeSent(this.message);
  final String message;
}

// Pull-to-refresh: re-fetches profile/roster/gps (the only remote data driver
// screens show — pickup/drop/check-in records are local-only and already
// current) without touching the global `loading` flag. Carries a completer so
// the RefreshIndicator on whichever tab triggered it can await completion.
class _DriverDataRefreshed extends DriverEvent {
  _DriverDataRefreshed(this.completer);
  final Completer<void> completer;
}

// Bus-position refresh while the Map tab is open (see _startMapPoll).
class _DriverGpsPolled extends DriverEvent {}

class DriverGeoRecord {
  const DriverGeoRecord({
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final DateTime time;
  final double latitude;
  final double longitude;
  final double accuracy;

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
  };

  factory DriverGeoRecord.fromJson(Map<String, dynamic> json) {
    return DriverGeoRecord(
      time: DateTime.tryParse('${json['time']}') ?? DateTime.now(),
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
    );
  }
}

class DriverState {
  const DriverState({
    required this.loading,
    required this.selectedIndex,
    required this.students,
    required this.driver,
    required this.vehicle,
    required this.gps,
    required this.pickedAt,
    required this.droppedAt,
    required this.checkIn,
    required this.checkOut,
    this.error,
    this.notice,
    this.routeTrail = const [],
  });

  factory DriverState.initial() => DriverState(
    loading: true,
    selectedIndex: 0,
    students: const [],
    driver: null,
    vehicle: null,
    gps: null,
    pickedAt: const {},
    droppedAt: const {},
    checkIn: null,
    checkOut: null,
  );

  final bool loading;
  final int selectedIndex;
  final List<Student> students;
  final Driver? driver;
  final Vehicle? vehicle;
  final GpsPoint? gps;
  /// Where the bus has been today, oldest first -- drawn as the route line.
  final List<GpsPoint> routeTrail;
  final Map<int, DriverGeoRecord> pickedAt;
  final Map<int, DriverGeoRecord> droppedAt;
  final DriverGeoRecord? checkIn;
  final DriverGeoRecord? checkOut;
  final String? error;
  final String? notice;

  DriverGeoRecord? get todayCheckIn => _todayRecord(checkIn);
  DriverGeoRecord? get todayCheckOut => _todayRecord(checkOut);
  int get pickedCount =>
      pickedAt.values.where((record) => _isToday(record.time)).length;
  int get droppedCount =>
      droppedAt.values.where((record) => _isToday(record.time)).length;
  bool get dutyStarted => todayCheckIn != null && todayCheckOut == null;

  DriverState copyWith({
    bool? loading,
    int? selectedIndex,
    List<Student>? students,
    Driver? driver,
    Vehicle? vehicle,
    GpsPoint? gps,
    List<GpsPoint>? routeTrail,
    Map<int, DriverGeoRecord>? pickedAt,
    Map<int, DriverGeoRecord>? droppedAt,
    DriverGeoRecord? checkIn,
    DriverGeoRecord? checkOut,
    String? error,
    String? notice,
    bool clearError = false,
    bool clearNotice = false,
    bool clearCheckIn = false,
    bool clearCheckOut = false,
  }) {
    return DriverState(
      loading: loading ?? this.loading,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      students: students ?? this.students,
      driver: driver ?? this.driver,
      vehicle: vehicle ?? this.vehicle,
      gps: gps ?? this.gps,
      routeTrail: routeTrail ?? this.routeTrail,
      pickedAt: pickedAt ?? this.pickedAt,
      droppedAt: droppedAt ?? this.droppedAt,
      checkIn: clearCheckIn ? null : checkIn ?? this.checkIn,
      checkOut: clearCheckOut ? null : checkOut ?? this.checkOut,
      error: clearError ? null : error ?? this.error,
      notice: clearNotice ? null : notice ?? this.notice,
    );
  }
}

class DriverBloc extends Bloc<DriverEvent, DriverState> {
  DriverBloc(
    this.campusRepository, {
    required this.driverPhone,
    required this.onSessionExpired,
  }) : super(DriverState.initial()) {
    on<DriverStarted>(_started);
    on<DriverRefreshed>(_started);
    on<DriverTabChanged>((event, emit) {
      emit(state.copyWith(selectedIndex: event.index));
      // Only poll while the driver is actually looking at the map. Opening it
      // fetches straight away, so it never starts on a position minutes old.
      if (event.index == _mapTabIndex) {
        _startMapPoll();
      } else {
        _stopMapPoll();
      }
    });
    on<DriverDutyCheckedIn>(_checkedIn);
    on<DriverDutyCheckedOut>(_checkedOut);
    on<DriverPicked>(_picked);
    on<DriverDropped>(_dropped);
    on<DriverNoticeSent>(_noticeSent);
    on<_DriverDataRefreshed>(_refreshData);
    on<_DriverGpsPolled>(_pollGps);
  }

  final CampusRepository campusRepository;
  final String driverPhone;
  final VoidCallback onSessionExpired;

  /// The Map tab, where the live map lives.
  static const _mapTabIndex = 2;

  /// Matches the backend's own poll interval: it refreshes from the provider
  /// every 90 seconds, so asking more often only re-reads the same row.
  static const _mapPollInterval = Duration(seconds: 90);

  Timer? _mapPoll;

  void _startMapPoll() {
    _mapPoll?.cancel();
    add(_DriverGpsPolled());
    _mapPoll = Timer.periodic(_mapPollInterval, (_) => add(_DriverGpsPolled()));
  }

  void _stopMapPoll() {
    _mapPoll?.cancel();
    _mapPoll = null;
  }

  @override
  Future<void> close() {
    _stopMapPoll();
    return super.close();
  }

  // Refreshes only the bus position and today's trail. A failed poll leaves
  // what is already on screen and the next tick tries again.
  Future<void> _pollGps(_DriverGpsPolled event, Emitter<DriverState> emit) async {
    try {
      final gps = _gpsForVehicle(await _loadGpsPoints(), state.vehicle);
      final routeTrail = await _loadRouteTrail();
      if (gps == null && routeTrail == null) return;
      emit(state.copyWith(gps: gps, routeTrail: routeTrail));
    } on SessionExpiredException {
      onSessionExpired();
    }
  }

  Future<void> _started(DriverEvent event, Emitter<DriverState> emit) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final driver = await campusRepository.getDriverProfile();
      final roster = await campusRepository.getDriverRoster();
      final gpsRows = await _loadGpsPoints();
      final gps = _gpsForVehicle(gpsRows, roster.vehicle);
      final routeTrail = await _loadRouteTrail();
      final saved = await _loadRecords(driver.phone);
      final duty = await _loadDuty();
      final loaded = state.copyWith(
        loading: false,
        driver: driver,
        vehicle: roster.vehicle,
        students: roster.students,
        gps: gps,
        routeTrail: routeTrail,
        pickedAt: saved.picked,
        droppedAt: saved.dropped,
        checkIn: saved.checkIn,
        checkOut: saved.checkOut,
        clearError: true,
      );
      // The server's duty state wins over what the phone saved; the saved copy
      // is only a fallback for when the duty call itself fails.
      emit(duty == null ? loaded : _withDuty(loaded, duty));
    } on SessionExpiredException {
      emit(state.copyWith(loading: false));
      onSessionExpired();
    } catch (error) {
      emit(
        state.copyWith(
          loading: false,
          error: error.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  // The bus position is secondary on the driver screens. A real session expiry
  // must still bubble up (so we log out), but any other failure — e.g. a
  // backend without /driver/vehicle-positions yet — must not blank the profile
  // and roster the driver actually works from.
  Future<List<GpsPoint>> _loadGpsPoints() async {
    try {
      return await campusRepository.getDriverGpsPoints();
    } on SessionExpiredException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  // Today's trail for the map's route line and direction arrows. Null (not
  // empty) on failure, so a failed refresh keeps the trail already drawn
  // instead of wiping it; only a real session expiry escapes.
  Future<List<GpsPoint>?> _loadRouteTrail() async {
    try {
      final now = DateTime.now();
      return await campusRepository.getDriverRouteTrail(
        from: DateTime(now.year, now.month, now.day),
      );
    } on SessionExpiredException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  // Pull-to-refresh, callable from any driver tab. No global `loading` flag
  // toggle, so only the pulling tab's own RefreshIndicator spinner shows.
  Future<void> refreshData() {
    final completer = Completer<void>();
    add(_DriverDataRefreshed(completer));
    return completer.future;
  }

  Future<void> _refreshData(
    _DriverDataRefreshed event,
    Emitter<DriverState> emit,
  ) async {
    try {
      final driver = await campusRepository.getDriverProfile();
      final roster = await campusRepository.getDriverRoster();
      final gpsRows = await _loadGpsPoints();
      final gps = _gpsForVehicle(gpsRows, roster.vehicle);
      final routeTrail = await _loadRouteTrail();
      final duty = await _loadDuty();
      final refreshed = state.copyWith(
        driver: driver,
        vehicle: roster.vehicle,
        students: roster.students,
        gps: gps,
        routeTrail: routeTrail,
      );
      emit(duty == null ? refreshed : _withDuty(refreshed, duty));
      event.completer.complete();
    } on SessionExpiredException {
      onSessionExpired();
      event.completer.complete();
    } catch (error) {
      // Surfaced via the existing state.error -> SnackBar path (see
      // DriverHomePage's BlocConsumer listener) rather than rejecting the
      // completer, so refresh failures look the same as other app errors.
      emit(
        state.copyWith(error: error.toString().replaceFirst('Exception: ', '')),
      );
      event.completer.complete();
    }
  }

  Future<void> _checkedIn(
    DriverDutyCheckedIn event,
    Emitter<DriverState> emit,
  ) async {
    await _storeDutyLocation(emit, checkIn: true);
  }

  Future<void> _checkedOut(
    DriverDutyCheckedOut event,
    Emitter<DriverState> emit,
  ) async {
    await _storeDutyLocation(emit, checkIn: false);
  }

  Future<void> _picked(DriverPicked event, Emitter<DriverState> emit) async {
    await _storeStudentLocation(emit, event.studentId, pickup: true);
  }

  Future<void> _dropped(DriverDropped event, Emitter<DriverState> emit) async {
    await _storeStudentLocation(emit, event.studentId, pickup: false);
  }

  void _noticeSent(DriverNoticeSent event, Emitter<DriverState> emit) {
    emit(state.copyWith(notice: event.message, clearError: true));
  }

  Future<void> _storeDutyLocation(
    Emitter<DriverState> emit, {
    required bool checkIn,
  }) async {
    emit(state.copyWith(loading: true, clearError: true, clearNotice: true));
    try {
      final record = await _currentLocationRecord();
      // Sent to the backend first: this is what the admin attendance report and
      // the driver's On duty / Off duty status read. Only saved on the phone
      // once the server has accepted it, so a failure never shows as "saved".
      final duty = await campusRepository.recordDriverDuty(
        action: checkIn ? 'CheckIn' : 'CheckOut',
        latitude: record.latitude,
        longitude: record.longitude,
        accuracy: record.accuracy,
      );
      final next = _withDuty(state, duty).copyWith(
        loading: false,
        notice: checkIn
            ? 'Duty check-in saved with GPS location.'
            : 'Duty check-out saved with GPS location.',
      );
      await _saveRecords(next);
      emit(next);
    } on SessionExpiredException {
      emit(state.copyWith(loading: false));
      onSessionExpired();
    } catch (error) {
      // E.g. "You are already checked in" after checking in on another phone:
      // pull the server's state so the buttons match it.
      final duty = await _loadDuty().catchError((_) => null);
      final failed = state.copyWith(
        loading: false,
        error: error.toString().replaceFirst('Exception: ', ''),
      );
      emit(duty == null ? failed : _withDuty(failed, duty));
    }
  }

  // Null on any failure other than an expired session, so an older backend
  // without /driver/duty (or a network blip) falls back to the phone's copy.
  Future<DriverDuty?> _loadDuty() async {
    try {
      return await campusRepository.getDriverDuty();
    } on SessionExpiredException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  DriverState _withDuty(DriverState base, DriverDuty duty) {
    DriverGeoRecord? record(DutyEvent? event) => event == null
        ? null
        : DriverGeoRecord(
            time: event.time,
            latitude: event.latitude,
            longitude: event.longitude,
            accuracy: event.accuracy,
          );
    final checkIn = record(duty.checkIn);
    final checkOut = record(duty.checkOut);
    return base.copyWith(
      checkIn: checkIn,
      checkOut: checkOut,
      clearCheckIn: checkIn == null,
      clearCheckOut: checkOut == null,
    );
  }

  Future<void> _storeStudentLocation(
    Emitter<DriverState> emit,
    int studentId, {
    required bool pickup,
  }) async {
    emit(state.copyWith(loading: true, clearError: true, clearNotice: true));
    try {
      final record = await _currentLocationRecord();
      if (pickup) {
        final nextPicked = Map<int, DriverGeoRecord>.from(state.pickedAt);
        nextPicked[studentId] = record;
        await _createTransportLog(studentId, 'Pickup', record);
        final next = state.copyWith(
          loading: false,
          pickedAt: nextPicked,
          notice: 'Pickup saved with GPS location.',
        );
        await _saveRecords(next);
        emit(next);
      } else {
        final nextDropped = Map<int, DriverGeoRecord>.from(state.droppedAt);
        nextDropped[studentId] = record;
        await _createTransportLog(studentId, 'Drop', record);
        final next = state.copyWith(
          loading: false,
          droppedAt: nextDropped,
          notice: 'Drop saved with GPS location.',
        );
        await _saveRecords(next);
        emit(next);
      }
    } on SessionExpiredException {
      emit(state.copyWith(loading: false));
      onSessionExpired();
    } catch (error) {
      emit(
        state.copyWith(
          loading: false,
          error: error.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  Future<DriverGeoRecord> _currentLocationRecord() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw Exception('Location service is off. Turn on GPS and try again.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required to save GPS proof.');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
    return DriverGeoRecord(
      time: DateTime.now(),
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }

  Future<void> _createTransportLog(
    int studentId,
    String action,
    DriverGeoRecord record,
  ) {
    return campusRepository.createTransportLog(
      studentId: studentId,
      action: action,
      recordedAt: record.time,
      latitude: record.latitude,
      longitude: record.longitude,
      accuracy: record.accuracy,
    );
  }

  String get _storageKey => 'driver_records_${_onlyDigits(driverPhone)}';

  Future<_SavedDriverRecords> _loadRecords(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString('driver_records_${_onlyDigits(phone)}');
    if (text == null || text.isEmpty) return _SavedDriverRecords.empty();
    final json = jsonDecode(text) as Map<String, dynamic>;
    return _SavedDriverRecords.fromJson(json);
  }

  Future<void> _saveRecords(DriverState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode({
        'checkIn': state.checkIn?.toJson(),
        'checkOut': state.checkOut?.toJson(),
        'picked': state.pickedAt.map(
          (key, value) => MapEntry('$key', value.toJson()),
        ),
        'dropped': state.droppedAt.map(
          (key, value) => MapEntry('$key', value.toJson()),
        ),
      }),
    );
  }
}

class _SavedDriverRecords {
  const _SavedDriverRecords({
    required this.checkIn,
    required this.checkOut,
    required this.picked,
    required this.dropped,
  });

  final DriverGeoRecord? checkIn;
  final DriverGeoRecord? checkOut;
  final Map<int, DriverGeoRecord> picked;
  final Map<int, DriverGeoRecord> dropped;

  factory _SavedDriverRecords.empty() => const _SavedDriverRecords(
    checkIn: null,
    checkOut: null,
    picked: {},
    dropped: {},
  );

  factory _SavedDriverRecords.fromJson(Map<String, dynamic> json) {
    DriverGeoRecord? maybeRecord(Object? value) {
      if (value is Map<String, dynamic>) return DriverGeoRecord.fromJson(value);
      return null;
    }

    Map<int, DriverGeoRecord> mapRecords(Object? value) {
      if (value is! Map<String, dynamic>) return {};
      return value.map(
        (key, item) => MapEntry(
          int.tryParse(key) ?? 0,
          DriverGeoRecord.fromJson(item as Map<String, dynamic>),
        ),
      )..removeWhere((key, _) => key == 0);
    }

    return _SavedDriverRecords(
      checkIn: maybeRecord(json['checkIn']),
      checkOut: maybeRecord(json['checkOut']),
      picked: mapRecords(json['picked']),
      dropped: mapRecords(json['dropped']),
    );
  }
}

GpsPoint? _gpsForVehicle(List<GpsPoint> gpsRows, Vehicle? vehicle) {
  if (vehicle == null) return gpsRows.firstOrNull;
  for (final gps in gpsRows) {
    if (gps.vehicleNo == vehicle.id || gps.alias == vehicle.route) return gps;
  }
  return gpsRows.firstOrNull;
}

String _onlyDigits(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
}

bool _isToday(DateTime value) {
  final now = DateTime.now();
  return value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;
}

DriverGeoRecord? _todayRecord(DriverGeoRecord? record) {
  if (record == null || !_isToday(record.time)) return null;
  return record;
}
