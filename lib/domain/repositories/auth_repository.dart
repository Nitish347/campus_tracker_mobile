import '../entities/auth_session.dart';
import '../entities/user_role.dart';

abstract class AuthRepository {
  Future<AuthSession?> restoreSession();

  /// Returns a dev-mode OTP hint when the backend has no SMS provider
  /// configured (see BUG_ANALYSIS.md, C4); null once real SMS delivery exists.
  Future<String?> requestOtp({required UserRole role, required String phone});
  Future<AuthSession> verifyOtp({
    required UserRole role,
    required String phone,
    required String otp,
  });
  Future<void> logout();
}
