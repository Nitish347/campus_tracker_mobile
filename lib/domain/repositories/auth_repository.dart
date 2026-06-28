import '../entities/auth_session.dart';
import '../entities/user_role.dart';

abstract class AuthRepository {
  Future<AuthSession?> restoreSession();
  Future<void> requestOtp({required UserRole role, required String phone});
  Future<AuthSession> verifyOtp({
    required UserRole role,
    required String phone,
    required String otp,
  });
  Future<void> logout();
}
