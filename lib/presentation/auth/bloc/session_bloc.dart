import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api_log.dart';
import '../../../domain/entities/auth_session.dart';
import '../../../domain/repositories/auth_repository.dart';

abstract class SessionEvent {}

class SessionStarted extends SessionEvent {}

class SessionAuthenticated extends SessionEvent {
  SessionAuthenticated(this.session);
  final AuthSession session;
}

class SessionLoggedOut extends SessionEvent {}

class SessionState {
  const SessionState({required this.loading, this.session});

  final bool loading;
  final AuthSession? session;
}

class SessionBloc extends Bloc<SessionEvent, SessionState> {
  SessionBloc(this.authRepository) : super(const SessionState(loading: true)) {
    on<SessionStarted>(_started);
    on<SessionAuthenticated>((event, emit) {
      sessionLog('SessionAuthenticated -> routing to ${event.session.role.name} home');
      emit(SessionState(loading: false, session: event.session));
    });
    on<SessionLoggedOut>(_loggedOut);
  }

  final AuthRepository authRepository;

  Future<void> _started(
    SessionStarted event,
    Emitter<SessionState> emit,
  ) async {
    final session = await authRepository.restoreSession();
    sessionLog(
      session == null
          ? 'SessionStarted -> no stored session, showing login'
          : 'SessionStarted -> restored ${session.role.name} session',
    );
    emit(SessionState(loading: false, session: session));
  }

  Future<void> _loggedOut(
    SessionLoggedOut event,
    Emitter<SessionState> emit,
  ) async {
    // StackTrace.current names the bloc that called onSessionExpired(), which
    // is what tells us *which screen's* request triggered the logout.
    sessionLog(
      'LOGOUT dispatched. Trigger:\n${StackTrace.current.toString().split('\n').take(8).join('\n')}',
    );
    await authRepository.logout();
    emit(const SessionState(loading: false));
  }
}
