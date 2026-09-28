import 'user_role.dart';

class AuthSession {
  const AuthSession({
    required this.role,
    required this.phone,
    required this.token,
  });

  final UserRole role;
  final String phone;
  final String token;
}
