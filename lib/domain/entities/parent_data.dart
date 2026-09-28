import 'gps_point.dart';
import 'notification_item.dart';
import 'payment_record.dart';
import 'fee_due.dart';
import 'student.dart';
import 'transport_log.dart';
import 'vehicle.dart';

class ParentData {
  const ParentData({
    required this.vehicles,
    required this.students,
    required this.gps,
    required this.feeDues,
    required this.payments,
    required this.transportLogs,
    this.notifications = const [],
  });

  final List<Vehicle> vehicles;
  final List<Student> students;
  final List<GpsPoint> gps;
  final List<FeeDue> feeDues;
  final List<PaymentRecord> payments;
  final List<TransportLog> transportLogs;
  final List<NotificationItem> notifications;

  ParentData copyWith({
    List<Vehicle>? vehicles,
    List<Student>? students,
    List<GpsPoint>? gps,
    List<FeeDue>? feeDues,
    List<PaymentRecord>? payments,
    List<TransportLog>? transportLogs,
    List<NotificationItem>? notifications,
  }) {
    return ParentData(
      vehicles: vehicles ?? this.vehicles,
      students: students ?? this.students,
      gps: gps ?? this.gps,
      feeDues: feeDues ?? this.feeDues,
      payments: payments ?? this.payments,
      transportLogs: transportLogs ?? this.transportLogs,
      notifications: notifications ?? this.notifications,
    );
  }
}
