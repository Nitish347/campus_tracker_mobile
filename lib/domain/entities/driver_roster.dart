import 'student.dart';
import 'vehicle.dart';

class DriverRoster {
  const DriverRoster({required this.vehicle, required this.students});

  final Vehicle? vehicle;
  final List<Student> students;
}
