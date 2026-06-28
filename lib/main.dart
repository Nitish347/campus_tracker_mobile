import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'data/datasources/campus_remote_data_source.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'data/repositories/campus_repository_impl.dart';
import 'domain/entities/user_role.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/campus_repository.dart';
import 'presentation/auth/bloc/session_bloc.dart';
import 'presentation/auth/pages/login_page.dart';
import 'presentation/driver/bloc/driver_bloc.dart';
import 'presentation/driver/pages/driver_home_page.dart';
import 'presentation/parent/bloc/parent_bloc.dart';
import 'presentation/parent/pages/parent_home_page.dart';

void main() {
  final remoteDataSource = CampusRemoteDataSource();
  final campusRepository = CampusRepositoryImpl(remoteDataSource);
  final authRepository = AuthRepositoryImpl(remoteDataSource);

  runApp(
    CampusTrackerApp(
      campusRepository: campusRepository,
      authRepository: authRepository,
    ),
  );
}

class CampusTrackerApp extends StatelessWidget {
  const CampusTrackerApp({
    super.key,
    required this.campusRepository,
    required this.authRepository,
  });

  final CampusRepository campusRepository;
  final AuthRepository authRepository;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<CampusRepository>.value(value: campusRepository),
        RepositoryProvider<AuthRepository>.value(value: authRepository),
      ],
      child: BlocProvider(
        create: (_) => SessionBloc(authRepository)..add(SessionStarted()),
        child: MaterialApp(
          title: 'Campus Tracker',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff0f6b55),
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xfff3f7f5),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xffdfe8e4)),
              ),
            ),
          ),
          home: const SessionGate(),
        ),
      ),
    );
  }
}

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionBloc, SessionState>(
      builder: (context, state) {
        if (state.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = state.session;
        if (session == null) {
          return LoginPage(
            onAuthenticated: (session) {
              context.read<SessionBloc>().add(SessionAuthenticated(session));
            },
          );
        }

        if (session.role == UserRole.parent) {
          return BlocProvider(
            create: (_) =>
                ParentBloc(context.read<CampusRepository>())
                  ..add(ParentStarted()),
            child: const ParentHomePage(),
          );
        }

        return BlocProvider(
          create: (_) =>
              DriverBloc(context.read<CampusRepository>())
                ..add(DriverStarted()),
          child: const DriverHomePage(),
        );
      },
    );
  }
}
