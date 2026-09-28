class TransportLog {
  const TransportLog({
    required this.id,
    required this.studentId,
    required this.action,
    required this.recordedAt,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final int id;
  final int studentId;
  final String action;
  final DateTime recordedAt;
  final double latitude;
  final double longitude;
  final double accuracy;
}
