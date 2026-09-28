class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.studentId,
    required this.student,
    required this.plan,
    required this.amount,
    required this.date,
    required this.method,
    required this.status,
  });

  final String id;
  final int studentId;
  final String student;
  final String plan;
  final num amount;
  final DateTime date;
  final String method;
  final String status;
}
