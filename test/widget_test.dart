import 'package:campus_tracker_mobile/main.dart';
import 'package:campus_tracker_mobile/data/datasources/campus_remote_data_source.dart';
import 'package:campus_tracker_mobile/data/repositories/auth_repository_impl.dart';
import 'package:campus_tracker_mobile/data/repositories/campus_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows role login choices', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final campusRepository = CampusRepositoryImpl(CampusRemoteDataSource());

    await tester.pumpWidget(
      CampusTrackerApp(
        campusRepository: campusRepository,
        authRepository: AuthRepositoryImpl(CampusRemoteDataSource()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Adimove'), findsOneWidget);
    expect(find.text('Parent'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
  });
}
