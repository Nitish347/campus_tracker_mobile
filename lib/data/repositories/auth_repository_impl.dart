import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_log.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/user_role.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/campus_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this.remoteDataSource);

  final CampusRemoteDataSource remoteDataSource;

  static const _roleKey = 'auth_role';
  static const _phoneKey = 'auth_phone';
  static const _tokenKey = 'auth_token';

  @override
  Future<AuthSession?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final roleName = prefs.getString(_roleKey);
    final phone = prefs.getString(_phoneKey);
    final token = prefs.getString(_tokenKey);
    final role = roleName == UserRole.driver.name
        ? UserRole.driver
        : roleName == UserRole.parent.name
        ? UserRole.parent
        : null;
    if (role == null || phone == null || token == null || token.isEmpty) {
      sessionLog(
        'restoreSession: incomplete stored session '
        '(role=$roleName phone=${phone == null ? 'null' : 'set'} token=${token == null ? 'null' : 'set'})',
      );
      return null;
    }
    sessionLog('restoreSession: ${describeToken(token)}');
    remoteDataSource.setSessionToken(token);
    return AuthSession(role: role, phone: phone, token: token);
  }

  @override
  Future<String?> requestOtp({
    required UserRole role,
    required String phone,
  }) async {
    final normalizedPhone = onlyDigits(phone);
    if (normalizedPhone.length != 10) {
      throw Exception('Enter a valid 10 digit phone number.');
    }
    return switch (role) {
      UserRole.parent => remoteDataSource.requestParentOtp(normalizedPhone),
      UserRole.driver => remoteDataSource.requestDriverOtp(normalizedPhone),
    };
  }

  @override
  Future<AuthSession> verifyOtp({
    required UserRole role,
    required String phone,
    required String otp,
  }) async {
    final normalizedPhone = onlyDigits(phone);
    final token = await switch (role) {
      UserRole.parent => remoteDataSource.verifyParentOtp(normalizedPhone, otp),
      UserRole.driver => remoteDataSource.verifyDriverOtp(normalizedPhone, otp),
    };

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleKey, role.name);
    await prefs.setString(_phoneKey, normalizedPhone);
    await prefs.setString(_tokenKey, token);
    remoteDataSource.setSessionToken(token);
    return AuthSession(role: role, phone: normalizedPhone, token: token);
  }

  @override
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
    await prefs.remove(_phoneKey);
    await prefs.remove(_tokenKey);
    remoteDataSource.setSessionToken(null);
  }
}
