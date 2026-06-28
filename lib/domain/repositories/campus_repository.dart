import '../entities/driver.dart';
import '../entities/gps_point.dart';
import '../entities/student.dart';
import '../entities/vehicle.dart';

abstract class CampusRepository {
  Future<List<Vehicle>> getVehicles();
  Future<List<Student>> getStudents();
  Future<List<Driver>> getDrivers();
  Future<List<GpsPoint>> getGpsPoints({String? baseUrl, String? username});
}
