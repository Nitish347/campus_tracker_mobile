import 'package:flutter_test/flutter_test.dart';
import 'package:campus_tracker_mobile/domain/entities/student.dart';
import 'package:campus_tracker_mobile/presentation/parent/pages/parent_home_page.dart';

Student child(String branch) => Student(
      id: 1, name: 'A', regNo: 'R', className: '5', phone: '', secondaryPhone: '',
      vehicle: 'BUS-01', area: '-', route: '-', monthlyDue: 0, branch: branch,
    );

void main() {
  test('one child, branch set -> that branch', () {
    expect(branchForPayment([child('JPIS')]), 'JPIS');
    expect(branchForPayment([child('JPS')]), 'JPS');
  });

  test('branch unset -> no branch, so no button', () {
    expect(branchForPayment([child('')]), '');
    expect(branchForPayment([]), '');
  });

  test('case and spacing are tolerated', () {
    expect(branchForPayment([child(' jpis ')]), 'JPIS');
  });

  test('siblings at the same school -> that branch', () {
    expect(branchForPayment([child('JPS'), child('JPS')]), 'JPS');
  });

  test('siblings at different schools -> no button rather than a wrong one', () {
    expect(branchForPayment([child('JPS'), child('JPIS')]), '');
  });

  test('one sibling set, one blank -> still resolves', () {
    expect(branchForPayment([child('JPIS'), child('')]), 'JPIS');
  });
}
