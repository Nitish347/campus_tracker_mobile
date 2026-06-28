import 'gps_point.dart';
import 'student.dart';
import 'vehicle.dart';

class ParentData {
  const ParentData({
    required this.vehicles,
    required this.students,
    required this.gps,
  });

  final List<Vehicle> vehicles;
  final List<Student> students;
  final List<GpsPoint> gps;
}
