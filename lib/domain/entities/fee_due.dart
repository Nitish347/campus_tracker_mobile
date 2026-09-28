class FeeDue {
  const FeeDue({
    required this.id,
    required this.studentId,
    required this.student,
    required this.month,
    required this.billed,
    required this.paidAmount,
    required this.balance,
    required this.status,
  });

  final int id;
  final int studentId;
  final String student;
  final String month;
  final num billed;
  final num paidAmount;
  final num balance;
  final String status;
}
