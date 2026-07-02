import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/app_constants.dart';
import '../../domain/entities/driver.dart';
import '../../domain/entities/gps_point.dart';
import '../../domain/entities/student.dart';
import '../../domain/entities/vehicle.dart';

class CampusRemoteDataSource {
  Future<String> resolveApiBaseUrl() async {
    Object? lastError;
    for (final baseUrl in apiBaseUrls.where((url) => url.isNotEmpty)) {
      try {
        final response = await http
            .get(Uri.parse('$baseUrl/health'))
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) return baseUrl;
        lastError = Exception(
          '$baseUrl/health returned ${response.statusCode}',
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception('No API host responded. Last error: $lastError');
  }

  Future<List<Vehicle>> fetchVehicles() async {
    final rows = await _getList('/vehicles');
    return rows.map((row) => _vehicleFromJson(row)).toList();
  }

  Future<List<Student>> fetchStudents() async {
    final rows = await _getList('/students');
    return rows.map((row) => _studentFromJson(row)).toList();
  }

  Future<List<Driver>> fetchDrivers() async {
    final rows = await _getList('/drivers');
    return rows.map((row) => _driverFromJson(row)).toList();
  }

  Future<List<GpsPoint>> fetchGpsPoints({
    String? baseUrl,
    String? username,
  }) async {
    if (baseUrl == null ||
        baseUrl.isEmpty ||
        username == null ||
        username.isEmpty) {
      return const [];
    }
    final response = await http
        .get(
          Uri.parse(
            '${baseUrl.replaceFirst(RegExp(r'/$'), '')}/gps/public/api/v1/company',
          ),
          headers: {'username': username},
        )
        .timeout(const Duration(seconds: 5));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (payload['code'] != 0 || payload['data'] is! List) return const [];
    return (payload['data'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(_gpsFromJson)
        .toList();
  }

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    Object? lastError;
    for (final baseUrl in apiBaseUrls.where((url) => url.isNotEmpty)) {
      try {
        await http
            .get(Uri.parse('$baseUrl/health'))
            .timeout(const Duration(seconds: 4));
        final response = await http
            .get(Uri.parse('$baseUrl$path'))
            .timeout(const Duration(seconds: 4));
        if (response.statusCode != 200) {
          lastError = Exception(
            'Request failed with status ${response.statusCode}',
          );
          continue;
        }
        return (jsonDecode(response.body) as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .toList();
      } catch (error) {
        lastError = '$baseUrl$path failed: $error';
      }
    }
    throw Exception('Backend is not reachable. $lastError');
  }
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
  final millis = json['timestamp'] is num
      ? (json['timestamp'] as num).toInt()
      : DateTime.now().millisecondsSinceEpoch;
  return GpsPoint(
    vehicleNo: '${json['vehicleNo'] ?? ''}',
    latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    speed: json['speed'] is num ? json['speed'] as num : 0,
    ignition: json['ignition'] == true,
    odometer: json['totalGpsOdometer'] is num
        ? json['totalGpsOdometer'] as num
        : 0,
    timestamp: DateTime.fromMillisecondsSinceEpoch(millis),
    alias: json['alias']?.toString(),
    imei: json['Imei']?.toString() ?? json['imei']?.toString(),
  );
}

int _intValue(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

String onlyDigits(String value) => value.replaceAll(RegExp(r'\D'), '');
