/// One duty check-in or check-out, as recorded by the backend.
class DutyEvent {
  const DutyEvent({
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  /// Server time, in the device's local zone.
  final DateTime time;
  final double latitude;
  final double longitude;
  final double accuracy;
}

/// The driver's duty state for today, as the backend sees it.
///
/// [checkIn] is the latest check-in and [checkOut] the check-out that closed
/// it, if any. A driver can check in again after checking out.
class DriverDuty {
  const DriverDuty({
    required this.onDuty,
    required this.checkIn,
    required this.checkOut,
  });

  final bool onDuty;
  final DutyEvent? checkIn;
  final DutyEvent? checkOut;
}
