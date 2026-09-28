import '../entities/driver.dart';
import '../entities/driver_duty.dart';
import '../entities/driver_roster.dart';
import '../entities/fee_due.dart';
import '../entities/gps_point.dart';
import '../entities/notification_item.dart';
import '../entities/payment_record.dart';
import '../entities/student.dart';
import '../entities/transport_log.dart';
import '../entities/vehicle.dart';

/// Every method here hits a backend endpoint that is already scoped server-side
/// to the signed-in parent/driver's own phone number — no client-side filtering
/// of a full admin-wide list is needed (or possible) any more.
abstract class CampusRepository {
  Future<List<Student>> getParentChildren();
  Future<List<Vehicle>> getParentVehicles();
  Future<List<FeeDue>> getParentFeeDues({String? month});
  Future<List<PaymentRecord>> getParentPayments();
  Future<List<TransportLog>> getParentTransportLogs({int? studentId});
  Future<List<NotificationItem>> getParentNotifications();
  Future<void> markParentNotificationsRead();
  Future<void> registerParentDeviceToken(String token, String platform);

  Future<Driver> getDriverProfile();
  Future<DriverRoster> getDriverRoster();
  Future<void> registerDriverDeviceToken(String token, String platform);

  /// Today's duty check-in / check-out as stored on the backend.
  Future<DriverDuty> getDriverDuty();

  /// Records a duty check-in ([action] `CheckIn`) or check-out (`CheckOut`).
  /// The backend also moves the driver's status to On duty / Off duty.
  Future<DriverDuty> recordDriverDuty({
    required String action,
    required double latitude,
    required double longitude,
    required double accuracy,
  });

  /// Positions for this driver's own assigned bus only.
  Future<List<GpsPoint>> getDriverGpsPoints();

  /// Where this driver's own bus has been since [from], oldest first.
  Future<List<GpsPoint>> getDriverRouteTrail({required DateTime from});

  /// Positions for this parent's own children's bus only.
  Future<List<GpsPoint>> getParentGpsPoints();

  /// Where one child's bus has been since [from], oldest first.
  Future<List<GpsPoint>> getParentRouteTrail({
    required int studentId,
    required DateTime from,
  });

  /// Latest position for one bus, or null when none has been reported.
  Future<GpsPoint?> getGpsPointForVehicle(String vehicle);

  Future<void> createTransportLog({
    required int studentId,
    required String action,
    required DateTime recordedAt,
    required double latitude,
    required double longitude,
    required double accuracy,
  });
}
