import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/auth_session.dart';
import '../../../domain/entities/user_role.dart';
import '../../../domain/repositories/auth_repository.dart';

abstract class LoginEvent {}

class LoginRoleChanged extends LoginEvent {
  LoginRoleChanged(this.role);
  final UserRole role;
}

class LoginPhoneChanged extends LoginEvent {
  LoginPhoneChanged(this.phone);
  final String phone;
}

class LoginOtpChanged extends LoginEvent {
  LoginOtpChanged(this.otp);
  final String otp;
}

class LoginOtpRequested extends LoginEvent {}

class LoginOtpVerified extends LoginEvent {}

class LoginState {
  const LoginState({
    required this.role,
    required this.phone,
    required this.otp,
    required this.otpRequested,
    required this.loading,
    this.error,
    this.session,
  });

  factory LoginState.initial() => const LoginState(
    role: UserRole.parent,
    phone: '',
    otp: '',
    otpRequested: false,
    loading: false,
  );

  final UserRole role;
  final String phone;
  final String otp;
  final bool otpRequested;
  final bool loading;
  final String? error;
  final AuthSession? session;

  LoginState copyWith({
    UserRole? role,
    String? phone,
    String? otp,
    bool? otpRequested,
    bool? loading,
    String? error,
    AuthSession? session,
    bool clearError = false,
  }) {
    return LoginState(
      role: role ?? this.role,
      phone: phone ?? this.phone,
      otp: otp ?? this.otp,
      otpRequested: otpRequested ?? this.otpRequested,
      loading: loading ?? this.loading,
      error: clearError ? null : error ?? this.error,
      session: session ?? this.session,
    );
  }
}

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc(this.authRepository) : super(LoginState.initial()) {
    on<LoginRoleChanged>((event, emit) {
      emit(LoginState.initial().copyWith(role: event.role));
    });
    on<LoginPhoneChanged>((event, emit) {
      emit(
        state.copyWith(
          phone: event.phone.replaceAll(RegExp(r'\D'), ''),
          clearError: true,
        ),
      );
    });
    on<LoginOtpChanged>((event, emit) {
      emit(
        state.copyWith(
          otp: event.otp.replaceAll(RegExp(r'\D'), ''),
          clearError: true,
        ),
      );
    });
    on<LoginOtpRequested>(_requestOtp);
    on<LoginOtpVerified>(_verifyOtp);
  }

  final AuthRepository authRepository;

  Future<void> _requestOtp(
    LoginOtpRequested event,
    Emitter<LoginState> emit,
  ) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      await authRepository.requestOtp(role: state.role, phone: state.phone);
      emit(state.copyWith(loading: false, otpRequested: true, otp: ''));
    } catch (error) {
      emit(
        state.copyWith(
          loading: false,
          error: error.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }

  Future<void> _verifyOtp(
    LoginOtpVerified event,
    Emitter<LoginState> emit,
  ) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final session = await authRepository.verifyOtp(
        role: state.role,
        phone: state.phone,
        otp: state.otp,
      );
      emit(state.copyWith(loading: false, session: session));
    } catch (error) {
      emit(
        state.copyWith(
          loading: false,
          error: error.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }
}
