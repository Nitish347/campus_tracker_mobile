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
}
