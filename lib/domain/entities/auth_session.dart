import 'user_role.dart';

class AuthSession {
  const AuthSession({required this.role, required this.phone});

  final UserRole role;
  final String phone;
}
