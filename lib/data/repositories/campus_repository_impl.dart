import '../../domain/entities/driver.dart';
import '../../domain/entities/gps_point.dart';
import '../../domain/entities/student.dart';
import '../../domain/entities/vehicle.dart';
import '../../domain/repositories/campus_repository.dart';
import '../datasources/campus_remote_data_source.dart';
import '../demo_data.dart';

class CampusRepositoryImpl implements CampusRepository {
  CampusRepositoryImpl(this.remoteDataSource);

  final CampusRemoteDataSource remoteDataSource;

  @override
  Future<List<Vehicle>> getVehicles() async {
    try {
      final vehicles = await remoteDataSource.fetchVehicles();
      return vehicles.isEmpty ? demoVehicles : vehicles;
    } catch (_) {
      return demoVehicles;
    }
  }

  @override
  Future<List<Student>> getStudents() async {
    try {
      final students = await remoteDataSource.fetchStudents();
      return students.isEmpty ? demoStudents : students;
    } catch (_) {
      return demoStudents;
    }
  }

  @override
  Future<List<Driver>> getDrivers() async {
    try {
      final drivers = await remoteDataSource.fetchDrivers();
      return drivers.isEmpty ? demoDrivers : drivers;
    } catch (_) {
      return demoDrivers;
    }
  }

  @override
  Future<List<GpsPoint>> getGpsPoints({
    String? baseUrl,
    String? username,
  }) async {
    try {
      final gps = await remoteDataSource.fetchGpsPoints(
        baseUrl: baseUrl,
        username: username,
      );
      return gps.isEmpty ? demoGps : gps;
    } catch (_) {
      return demoGps;
    }
  }
}
