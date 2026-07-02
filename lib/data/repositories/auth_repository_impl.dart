import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_constants.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/user_role.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/campus_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this.remoteDataSource);

  final CampusRemoteDataSource remoteDataSource;

  static const _roleKey = 'auth_role';
  static const _phoneKey = 'auth_phone';

  @override
  Future<AuthSession?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final roleName = prefs.getString(_roleKey);
    final phone = prefs.getString(_phoneKey);
    final role = roleName == UserRole.driver.name
        ? UserRole.driver
        : roleName == UserRole.parent.name
        ? UserRole.parent
        : null;
    if (role == null || phone == null) return null;
    return AuthSession(role: role, phone: phone);
  }

  @override
  Future<void> requestOtp({
    required UserRole role,
    required String phone,
  }) async {
    final normalizedPhone = onlyDigits(phone);
    if (normalizedPhone.length != 10) {
      throw Exception('Enter a valid 10 digit phone number.');
    }

    final exists = await _phoneExists(role, normalizedPhone);

    if (!exists) {
      throw Exception('${role.label} phone number not found.');
    }
  }

  Future<bool> _phoneExists(UserRole role, String normalizedPhone) async {
    try {
      return switch (role) {
        UserRole.parent => (await remoteDataSource.fetchStudents()).any(
          (student) =>
              onlyDigits(student.phone) == normalizedPhone ||
              onlyDigits(student.secondaryPhone) == normalizedPhone,
        ),
        UserRole.driver => (await remoteDataSource.fetchDrivers()).any(
          (driver) => onlyDigits(driver.phone) == normalizedPhone,
        ),
      };
    } catch (error) {
      throw Exception(
        'Backend check failed: ${error.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  @override
  Future<AuthSession> verifyOtp({
    required UserRole role,
    required String phone,
    required String otp,
  }) async {
    final normalizedPhone = onlyDigits(phone);
    if (otp != demoOtp) {
      throw Exception('Invalid OTP. Use $demoOtp for demo login.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleKey, role.name);
    await prefs.setString(_phoneKey, normalizedPhone);
    return AuthSession(role: role, phone: normalizedPhone);
  }

  @override
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
    await prefs.remove(_phoneKey);
  }
}
