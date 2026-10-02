import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/api_log.dart';
import 'core/push_notifications.dart';
import 'data/datasources/campus_remote_data_source.dart'
    show CampusRemoteDataSource, SessionExpiredException;
import 'data/repositories/auth_repository_impl.dart';
import 'data/repositories/campus_repository_impl.dart';
import 'domain/entities/auth_session.dart';
import 'domain/entities/user_role.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/campus_repository.dart';
import 'presentation/auth/bloc/session_bloc.dart';
import 'presentation/auth/pages/login_page.dart';
import 'presentation/driver/bloc/driver_bloc.dart';
import 'presentation/driver/pages/driver_home_page.dart';
import 'presentation/parent/bloc/parent_bloc.dart';
import 'presentation/parent/pages/parent_home_page.dart';

// Catches Dart-level crashes that would otherwise just end the run with no
// clue why -- grep the device log for `[fatal]`. Native crashes (e.g. the
// iOS GoogleMaps SDK aborting without a key) don't go through Dart at all;
// those are logged separately in ios/Runner/AppDelegate.swift.
void _logFatal(String source, Object error, StackTrace stack) {
  debugPrint('[fatal] $source: $error');
  debugPrint('[fatal] $stack');
}

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (details) {
        _logFatal('FlutterError', details.exception, details.stack ?? StackTrace.current);
        FlutterError.presentError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        _logFatal('PlatformDispatcher', error, stack);
        return true;
      };

      // Firebase is optional at runtime — if the native config
      // (google-services.json / GoogleService-Info.plist) isn't present yet,
      // the app still runs, just without push delivery.
      try {
        await Firebase.initializeApp();
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      } catch (error) {
        debugPrint('Firebase not initialised (push disabled): $error');
      }

      final remoteDataSource = CampusRemoteDataSource();
      final campusRepository = CampusRepositoryImpl(remoteDataSource);
      final authRepository = AuthRepositoryImpl(remoteDataSource);

      runApp(
        CampusTrackerApp(
          campusRepository: campusRepository,
          authRepository: authRepository,
        ),
      );
    },
    (error, stack) => _logFatal('runZonedGuarded', error, stack),
  );
}

// Registers the device's FCM token with the backend for the signed-in user.
// Guarded so it only runs once per phone, and fire-and-forget so a push
// failure never blocks the UI.
String? _pushRegisteredFor;
Future<void> _registerPushToken(
  CampusRepository repository,
  AuthSession session,
) async {
  if (_pushRegisteredFor == session.phone) return;
  _pushRegisteredFor = session.phone;
  try {
    await PushNotifications.instance.init();
    final platform = PushNotifications.instance.platform;

    Future<void> send(String token) => session.role == UserRole.parent
        ? repository.registerParentDeviceToken(token, platform)
        : repository.registerDriverDeviceToken(token, platform);

    final token = await PushNotifications.instance.token();
    if (token != null && token.isNotEmpty) await send(token);
    PushNotifications.instance.onTokenRefresh.listen(send);
    sessionLog('push token registered for ${session.role.name}');
  } on SessionExpiredException {
    // Two different causes land here, told apart by the [api] line just above:
    //   "AUTH 401 on .../device-token" -> this call was rejected and cleared
    //      the shared session token itself.
    //   "BLOCKED .../device-token"     -> the token was already gone before we
    //      sent. Another request failed while the permission dialog was open;
    //      look further up the log for its AUTH 401.
    _pushRegisteredFor = null;
    sessionLog(
      'push registration for /${session.role.name}/device-token aborted: no '
      'valid session (see the [api] line above for which case)',
    );
  } catch (error) {
    _pushRegisteredFor = null; // allow a retry on the next build
    sessionLog('push token registration failed (non-auth): $error');
  }
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
          title: 'Adimove',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff0f6b55),
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xfff3f7f5),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              backgroundColor: Color(0xfff3f7f5),
              surfaceTintColor: Colors.transparent,
              titleTextStyle: TextStyle(
                color: Color(0xff172033),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            navigationBarTheme: NavigationBarThemeData(
              backgroundColor: Colors.white,
              indicatorColor: const Color(0xffdff4ec),
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  fontSize: 12,
                  fontWeight: states.contains(WidgetState.selected)
                      ? FontWeight.w900
                      : FontWeight.w600,
                ),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
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

        void onSessionExpired() =>
            context.read<SessionBloc>().add(SessionLoggedOut());

        // Register this device for push notifications for the signed-in user.
        _registerPushToken(context.read<CampusRepository>(), session);

        if (session.role == UserRole.parent) {
          return BlocProvider(
            create: (_) => ParentBloc(
              context.read<CampusRepository>(),
              parentPhone: session.phone,
              onSessionExpired: onSessionExpired,
            )..add(ParentStarted()),
            child: const ParentHomePage(),
          );
        }

        return BlocProvider(
          create: (_) => DriverBloc(
            context.read<CampusRepository>(),
            driverPhone: session.phone,
            onSessionExpired: onSessionExpired,
          )..add(DriverStarted()),
          child: const DriverHomePage(),
        );
      },
    );
  }
}
