import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/app_constants.dart';
import '../../../domain/entities/auth_session.dart';
import '../../../domain/entities/user_role.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../bloc/login_bloc.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.onAuthenticated});

  final ValueChanged<AuthSession> onAuthenticated;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => LoginBloc(context.read<AuthRepository>()),
      child: BlocConsumer<LoginBloc, LoginState>(
        listenWhen: (previous, current) => previous.session != current.session,
        listener: (context, state) {
          final session = state.session;
          if (session != null) onAuthenticated(session);
        },
        builder: (context, state) => Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.route,
                        size: 64,
                        color: Color(0xff0f6b55),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Campus Tracker',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Login with registered phone number',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 28),
                      SegmentedButton<UserRole>(
                        segments: const [
                          ButtonSegment(
                            value: UserRole.parent,
                            icon: Icon(Icons.family_restroom),
                            label: Text('Parent'),
                          ),
                          ButtonSegment(
                            value: UserRole.driver,
                            icon: Icon(Icons.drive_eta),
                            label: Text('Driver'),
                          ),
                        ],
                        selected: {state.role},
                        onSelectionChanged: state.loading
                            ? null
                            : (value) => context.read<LoginBloc>().add(
                                LoginRoleChanged(value.first),
                              ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        enabled: !state.otpRequested && !state.loading,
                        decoration: InputDecoration(
                          labelText: '${state.role.label} phone number',
                          counterText: '',
                          prefixText: '+91 ',
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) => context.read<LoginBloc>().add(
                          LoginPhoneChanged(value),
                        ),
                      ),
                      if (state.otpRequested) ...[
                        const SizedBox(height: 12),
                        TextField(
                          keyboardType: TextInputType.number,
                          maxLength: 4,
                          decoration: const InputDecoration(
                            labelText: 'OTP',
                            helperText: 'Demo OTP is $demoOtp',
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => context.read<LoginBloc>().add(
                            LoginOtpChanged(value),
                          ),
                        ),
                      ],
                      if (state.error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          state.error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: state.loading
                            ? null
                            : () => context.read<LoginBloc>().add(
                                state.otpRequested
                                    ? LoginOtpVerified()
                                    : LoginOtpRequested(),
                              ),
                        icon: state.loading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                state.otpRequested ? Icons.verified : Icons.sms,
                              ),
                        label: Text(
                          state.otpRequested ? 'Verify OTP' : 'Send OTP',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
