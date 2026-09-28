class Student {
  const Student({
    required this.id,
    required this.name,
    required this.regNo,
    required this.className,
    required this.phone,
    required this.secondaryPhone,
    required this.vehicle,
    required this.area,
    required this.route,
    required this.monthlyDue,
    required this.branch,
  });

  final int id;
  final String name;
  final String regNo;
  final String className;
  final String phone;
  final String secondaryPhone;
  final String vehicle;
  final String area;
  final String route;
  final num monthlyDue;

  /// JPC or JPIC, set by the admin. Decides which fee portal the parent is
  /// sent to, so an empty value must show no payment button at all rather
  /// than guessing one.
  final String branch;
}
