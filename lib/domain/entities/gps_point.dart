class GpsPoint {
  const GpsPoint({
    required this.vehicleNo,
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.ignition,
    required this.odometer,
    required this.timestamp,
    this.alias,
    this.imei,
  });

  final String vehicleNo;
  final double latitude;
  final double longitude;
  final num speed;
  final bool ignition;
  final num odometer;
  final DateTime timestamp;
  final String? alias;
  final String? imei;
}
