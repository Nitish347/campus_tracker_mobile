import '../../domain/entities/driver.dart';
import '../../domain/entities/driver_duty.dart';
import '../../domain/entities/driver_roster.dart';
import '../../domain/entities/fee_due.dart';
import '../../domain/entities/gps_point.dart';
import '../../domain/entities/notification_item.dart';
import '../../domain/entities/payment_record.dart';
import '../../domain/entities/student.dart';
import '../../domain/entities/transport_log.dart';
import '../../domain/entities/vehicle.dart';
import '../../domain/repositories/campus_repository.dart';
import '../datasources/campus_remote_data_source.dart';

class CampusRepositoryImpl implements CampusRepository {
  CampusRepositoryImpl(this.remoteDataSource);

  final CampusRemoteDataSource remoteDataSource;

  @override
  Future<List<Student>> getParentChildren() => remoteDataSource.fetchParentChildren();

  @override
  Future<List<PaymentRecord>> getParentPayments() => remoteDataSource.fetchParentPayments();

  @override
  Future<List<FeeDue>> getParentFeeDues({String? month}) =>
      remoteDataSource.fetchParentFeeDues(month: month);

  @override
  Future<List<TransportLog>> getParentTransportLogs({int? studentId}) =>
      remoteDataSource.fetchParentTransportLogs(studentId: studentId);

  @override
  Future<List<NotificationItem>> getParentNotifications() =>
      remoteDataSource.fetchParentNotifications();

  @override
  Future<void> markParentNotificationsRead() =>
      remoteDataSource.markParentNotificationsRead();

  @override
  Future<void> registerParentDeviceToken(String token, String platform) =>
      remoteDataSource.registerParentDeviceToken(token, platform);

  @override
  Future<void> registerDriverDeviceToken(String token, String platform) =>
      remoteDataSource.registerDriverDeviceToken(token, platform);

  @override
  Future<List<Vehicle>> getParentVehicles() => remoteDataSource.fetchParentVehicles();

  @override
  Future<Driver> getDriverProfile() => remoteDataSource.fetchDriverProfile();

  @override
  Future<DriverDuty> getDriverDuty() => remoteDataSource.fetchDriverDuty();

  @override
  Future<DriverDuty> recordDriverDuty({
    required String action,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) {
    return remoteDataSource.recordDriverDuty(
      action: action,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
    );
  }

  @override
  Future<DriverRoster> getDriverRoster() async {
    final result = await remoteDataSource.fetchDriverRoster();
    return DriverRoster(vehicle: result.vehicle, students: result.students);
  }

  @override
  Future<List<GpsPoint>> getDriverGpsPoints() {
    return remoteDataSource.fetchDriverGpsPoints();
  }

  @override
  Future<List<GpsPoint>> getDriverRouteTrail({required DateTime from}) {
    return remoteDataSource.fetchDriverRouteTrail(from: from);
  }

  @override
  Future<List<GpsPoint>> getParentGpsPoints() {
    return remoteDataSource.fetchParentGpsPoints();
  }

  @override
  Future<List<GpsPoint>> getParentRouteTrail({
    required int studentId,
    required DateTime from,
  }) {
    return remoteDataSource.fetchParentRouteTrail(
      studentId: studentId,
      from: from,
    );
  }

  @override
  Future<GpsPoint?> getGpsPointForVehicle(String vehicle) {
    return remoteDataSource.fetchGpsPointForVehicle(vehicle);
  }

  @override
  Future<void> createTransportLog({
    required int studentId,
    required String action,
    required DateTime recordedAt,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) {
    return remoteDataSource.createDriverTransportLog(
      studentId: studentId,
      action: action,
      recordedAt: recordedAt,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
    );
  }
}
