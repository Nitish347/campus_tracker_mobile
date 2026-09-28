class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.studentId,
  });

  final int id;
  final String type; // Pickup | Drop | FeeReminder
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;
  final int? studentId;
}
