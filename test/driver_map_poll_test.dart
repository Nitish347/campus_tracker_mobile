import 'package:flutter_test/flutter_test.dart';

import 'package:campus_tracker_mobile/domain/entities/driver.dart';
import 'package:campus_tracker_mobile/domain/entities/driver_duty.dart';
import 'package:campus_tracker_mobile/domain/entities/driver_roster.dart';
import 'package:campus_tracker_mobile/domain/entities/fee_due.dart';
import 'package:campus_tracker_mobile/domain/entities/gps_point.dart';
import 'package:campus_tracker_mobile/domain/entities/notification_item.dart';
import 'package:campus_tracker_mobile/domain/entities/payment_record.dart';
import 'package:campus_tracker_mobile/domain/entities/student.dart';
import 'package:campus_tracker_mobile/domain/entities/transport_log.dart';
import 'package:campus_tracker_mobile/domain/entities/vehicle.dart';
import 'package:campus_tracker_mobile/domain/repositories/campus_repository.dart';
import 'package:campus_tracker_mobile/presentation/driver/bloc/driver_bloc.dart';

/// Counts how often the driver's bus position is fetched.
class _CountingRepository implements CampusRepository {
  int gpsCalls = 0;

  @override
  Future<List<GpsPoint>> getDriverGpsPoints() async {
    gpsCalls += 1;
    return const [];
  }

  @override
  Future<List<GpsPoint>> getDriverRouteTrail({required DateTime from}) async => const [];
  @override
  Future<List<GpsPoint>> getParentRouteTrail({required int studentId, required DateTime from}) async => const [];
  @override
  Future<List<GpsPoint>> getParentGpsPoints() async => const [];
  @override
  Future<List<Vehicle>> getParentVehicles() async => const [];
  @override
  Future<List<Student>> getParentChildren() async => const [];
  @override
  Future<List<FeeDue>> getParentFeeDues({String? month}) async => const [];
  @override
  Future<List<PaymentRecord>> getParentPayments() async => const [];
  @override
  Future<List<TransportLog>> getParentTransportLogs({int? studentId}) async => const [];
  @override
  Future<List<NotificationItem>> getParentNotifications() async => const [];
  @override
  Future<void> markParentNotificationsRead() async {}
  @override
  Future<void> registerParentDeviceToken(String token, String platform) async {}
  @override
  Future<Driver> getDriverProfile() => throw UnimplementedError();
  @override
  Future<DriverRoster> getDriverRoster() => throw UnimplementedError();
  @override
  Future<DriverDuty> getDriverDuty() => throw UnimplementedError();
  @override
  Future<DriverDuty> recordDriverDuty({
    required String action,
    required double latitude,
    required double longitude,
    required double accuracy,
  }) => throw UnimplementedError();
  @override
  Future<void> registerDriverDeviceToken(String token, String platform) async {}
  @override
  Future<GpsPoint?> getGpsPointForVehicle(String vehicle) async => null;
  @override
  Future<void> createTransportLog({
    required int studentId,
    required String action,
    required double latitude,
    required double longitude,
    required double accuracy,
    required DateTime recordedAt,
  }) async {}
}

void main() {
  // testWidgets runs in a zone with a fake clock, so pump() advances timers
  // without the test waiting in real time.
  testWidgets('driver app polls the bus position only while Map is open',
      (tester) async {
    final repo = _CountingRepository();
    final bloc = DriverBloc(repo, driverPhone: '9111111111', onSessionExpired: () {});
    addTearDown(bloc.close);

    // On Duty: no timer should be running.
    bloc.add(DriverTabChanged(0));
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    expect(repo.gpsCalls, 0, reason: 'must not poll away from the map');

    // Open Map: one fetch straight away, then one every 90 seconds.
    bloc.add(DriverTabChanged(2));
    await tester.pump();
    await tester.pump(const Duration(minutes: 5));
    expect(repo.gpsCalls, 4, reason: '1 on open + 5 minutes at 90s = 4');

    // Leave Map: polling stops.
    final atSwitch = repo.gpsCalls;
    bloc.add(DriverTabChanged(3));
    await tester.pump();
    await tester.pump(const Duration(minutes: 10));
    expect(repo.gpsCalls, atSwitch, reason: 'must stop when the tab is left');
  });
}
