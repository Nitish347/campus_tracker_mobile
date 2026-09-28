import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xffdff4ec), Color(0xfff3f7f5)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const CircleAvatar(
                              radius: 36,
                              backgroundColor: Color(0xffe7f4ef),
                              child: Icon(
                                Icons.route,
                                size: 42,
                                color: Color(0xff0f6b55),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Adimove',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Secure transport access for parents and drivers',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 24),
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
                                filled: true,
                                fillColor: const Color(0xfff7fbf9),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onChanged: (value) => context
                                  .read<LoginBloc>()
                                  .add(LoginPhoneChanged(value)),
                            ),
                            if (state.otpRequested) ...[
                              const SizedBox(height: 12),
                              TextField(
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                decoration: InputDecoration(
                                  labelText: 'OTP',
                                  helperText: state.devOtp != null
                                      ? 'Demo OTP is ${state.devOtp}'
                                      : 'Enter the OTP sent to your phone',
                                  counterText: '',
                                  filled: true,
                                  fillColor: const Color(0xfff7fbf9),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onChanged: (value) => context
                                    .read<LoginBloc>()
                                    .add(LoginOtpChanged(value)),
                              ),
                            ],
                            if (state.error != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: .08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  state.error!,
                                  style: const TextStyle(color: Colors.red),
                                ),
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
                                      state.otpRequested
                                          ? Icons.verified
                                          : Icons.sms,
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
          ),
        ),
      ),
    );
  }
}
