import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/datasources/campus_remote_data_source.dart';
import '../../../domain/entities/gps_point.dart';
import '../../../domain/entities/notification_item.dart';
import '../../../domain/entities/parent_data.dart';
import '../../../domain/repositories/campus_repository.dart';

abstract class ParentEvent {}

class ParentStarted extends ParentEvent {}

class ParentRefreshed extends ParentEvent {}

class ParentTabChanged extends ParentEvent {
  ParentTabChanged(this.index);
  final int index;
}

class ParentStudentSelected extends ParentEvent {
  ParentStudentSelected(this.studentId);
  final int studentId;
}

// Pull-to-refresh for a single tab. Each carries a completer so the widget's
// RefreshIndicator can await exactly this fetch finishing (success or error)
// without waiting on — or triggering — a refresh of any other tab.
class _ParentSectionRefreshed extends ParentEvent {
  _ParentSectionRefreshed(this.section, this.completer);
  final _ParentSection section;
  final Completer<void> completer;
}

enum _ParentSection { home, tracking, history, fees, notifications }

class ParentState {
  const ParentState({
    required this.loading,
    required this.selectedIndex,
    required this.data,
    required this.selectedStudentId,
    this.error,
    this.routeTrail = const [],
  });

  factory ParentState.initial() => ParentState(
    loading: true,
    selectedIndex: 0,
    data: ParentData(
      vehicles: const [],
      students: const [],
      gps: const [],
      feeDues: const [],
      payments: const [],
      transportLogs: const [],
    ),
    selectedStudentId: 0,
  );

  final bool loading;
  final int selectedIndex;
  final ParentData data;
  final int selectedStudentId;
  final String? error;
  /// Where the selected child's bus has been today, oldest first.
  final List<GpsPoint> routeTrail;

  ParentState copyWith({
    bool? loading,
    int? selectedIndex,
    ParentData? data,
    int? selectedStudentId,
    String? error,
    List<GpsPoint>? routeTrail,
    bool clearError = false,
  }) {
    return ParentState(
      loading: loading ?? this.loading,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      data: data ?? this.data,
      selectedStudentId: selectedStudentId ?? this.selectedStudentId,
      error: clearError ? null : error ?? this.error,
      routeTrail: routeTrail ?? this.routeTrail,
    );
  }
}

class ParentBloc extends Bloc<ParentEvent, ParentState> {
  ParentBloc(
    this.campusRepository, {
    required this.parentPhone,
    required this.onSessionExpired,
  }) : super(ParentState.initial()) {
    on<ParentStarted>(_load);
    on<ParentRefreshed>(_load);
    on<ParentTabChanged>((event, emit) {
      emit(state.copyWith(selectedIndex: event.index));
      // Only poll while the parent is actually watching the map. A bus
      // position is of no use on the fees tab, and polling there would spend
      // battery and mobile data for nothing.
      if (event.index == _trackingTabIndex) {
        _startTrackingPoll();
      } else {
        _stopTrackingPoll();
      }
    });
    on<ParentStudentSelected>((event, emit) async {
      // Drop the previous child's trail at once, so it is never drawn against
      // the newly selected child's bus while theirs loads.
      emit(
        state.copyWith(
          selectedStudentId: event.studentId,
          routeTrail: const [],
        ),
      );
      try {
        final routeTrail = await _loadRouteTrail(event.studentId);
        // Ignore a reply that arrives after the parent picked someone else.
        if (routeTrail != null && state.selectedStudentId == event.studentId) {
          emit(state.copyWith(routeTrail: routeTrail));
        }
      } on SessionExpiredException {
        onSessionExpired();
      }
    });
    on<_ParentSectionRefreshed>(_refreshSection);
  }

  final CampusRepository campusRepository;
  final String parentPhone;
  final VoidCallback onSessionExpired;

  /// The Track tab, where the live map lives.
  static const _trackingTabIndex = 1;

  /// Matches the backend's own poll interval: it refreshes from the provider
  /// every 90 seconds, so asking more often only re-reads the same row.
  static const _trackingPollInterval = Duration(seconds: 90);

  Timer? _trackingPoll;

  void _startTrackingPoll() {
    _trackingPoll?.cancel();
    // Fetch straight away as well. Otherwise the map opens on wherever the bus
    // and its route were when they were last fetched -- possibly many minutes
    // ago -- and stays there until the first tick.
    _pollTracking();
    _trackingPoll = Timer.periodic(
      _trackingPollInterval,
      (_) => _pollTracking(),
    );
  }

  // A failed background poll must stay silent -- the parent did not ask for
  // this fetch, and the next tick will try again. Without catchError the
  // completer's rejection would surface as an unhandled error.
  void _pollTracking() {
    _requestSectionRefresh(_ParentSection.tracking).catchError((_) {});
  }

  void _stopTrackingPoll() {
    _trackingPoll?.cancel();
    _trackingPoll = null;
  }

  @override
  Future<void> close() {
    _stopTrackingPoll();
    return super.close();
  }

  Future<void> _load(ParentEvent event, Emitter<ParentState> emit) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final children = await campusRepository.getParentChildren();
      final vehicles = await campusRepository.getParentVehicles();
      final gps = await campusRepository.getParentGpsPoints();
      final feeDues = await campusRepository.getParentFeeDues();
      final payments = await campusRepository.getParentPayments();
      final transportLogs = await campusRepository.getParentTransportLogs();
      // Notifications are optional — a backend without this endpoint (or a
      // transient failure) must not break the whole parent screen.
      final notifications = await _loadNotifications();
      final selectedExists = children.any(
        (student) => student.id == state.selectedStudentId,
      );
      final selectedStudentId = selectedExists
          ? state.selectedStudentId
          : children.firstOrNull?.id ?? 0;
      final routeTrail = await _loadRouteTrail(selectedStudentId);
      emit(
        state.copyWith(
          loading: false,
          selectedStudentId: selectedStudentId,
          routeTrail: routeTrail,
          data: ParentData(
            vehicles: vehicles,
            students: children,
            gps: gps,
            feeDues: feeDues,
            payments: payments,
            transportLogs: transportLogs,
            notifications: notifications,
          ),
        ),
      );
    } on SessionExpiredException {
      emit(state.copyWith(loading: false));
      onSessionExpired();
    } catch (error) {
      emit(
        state.copyWith(
          loading: false,
          error: error.toString().replaceFirst('Exception: ', ''),
          data: const ParentData(
            vehicles: [],
            students: [],
            gps: [],
            feeDues: [],
            payments: [],
            transportLogs: [],
          ),
          selectedStudentId: 0,
          routeTrail: const [],
        ),
      );
    }
  }

  // A real session expiry must still bubble up (so we log out), but any other
  // failure — e.g. an older backend that lacks the notifications endpoint — is
  // swallowed so it never breaks the rest of the parent screen.
  Future<List<NotificationItem>> _loadNotifications() async {
    try {
      return await campusRepository.getParentNotifications();
    } on SessionExpiredException {
      rethrow;
    } catch (_) {
      return const [];
    }
  }

  // The selected child's bus route today, for the map's route line and
  // direction arrows. Null (not empty) on failure, so a failed refresh keeps
  // the trail already drawn; only a real session expiry escapes.
  Future<List<GpsPoint>?> _loadRouteTrail(int studentId) async {
    if (studentId <= 0) return const [];
    try {
      final now = DateTime.now();
      return await campusRepository.getParentRouteTrail(
        studentId: studentId,
        from: DateTime(now.year, now.month, now.day),
      );
    } on SessionExpiredException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  // Pull-to-refresh for a single tab: fetches only what that screen shows and
  // merges it into the existing data, instead of reloading everything — other
  // tabs, and the global `loading` flag, are left untouched.
  Future<void> refreshHome() => _requestSectionRefresh(_ParentSection.home);
  Future<void> refreshTracking() =>
      _requestSectionRefresh(_ParentSection.tracking);
  Future<void> refreshHistory() =>
      _requestSectionRefresh(_ParentSection.history);
  Future<void> refreshFees() => _requestSectionRefresh(_ParentSection.fees);
  Future<void> refreshNotifications() =>
      _requestSectionRefresh(_ParentSection.notifications);

  Future<void> _requestSectionRefresh(_ParentSection section) {
    final completer = Completer<void>();
    add(_ParentSectionRefreshed(section, completer));
    return completer.future;
  }

  Future<void> _refreshSection(
    _ParentSectionRefreshed event,
    Emitter<ParentState> emit,
  ) async {
    try {
      switch (event.section) {
        case _ParentSection.home:
          final vehicles = await campusRepository.getParentVehicles();
          final feeDues = await campusRepository.getParentFeeDues();
          final payments = await campusRepository.getParentPayments();
          final transportLogs = await campusRepository.getParentTransportLogs();
          emit(
            state.copyWith(
              data: state.data.copyWith(
                vehicles: vehicles,
                feeDues: feeDues,
                payments: payments,
                transportLogs: transportLogs,
              ),
            ),
          );
        case _ParentSection.tracking:
          final studentId = state.selectedStudentId;
          final vehicles = await campusRepository.getParentVehicles();
          final gps = await campusRepository.getParentGpsPoints();
          final routeTrail = await _loadRouteTrail(studentId);
          emit(
            state.copyWith(
              data: state.data.copyWith(vehicles: vehicles, gps: gps),
              // Only if the parent is still looking at the same child.
              routeTrail: state.selectedStudentId == studentId
                  ? routeTrail
                  : null,
            ),
          );
        case _ParentSection.history:
          final transportLogs = await campusRepository.getParentTransportLogs();
          emit(
            state.copyWith(
              data: state.data.copyWith(transportLogs: transportLogs),
            ),
          );
        case _ParentSection.fees:
          final feeDues = await campusRepository.getParentFeeDues();
          final payments = await campusRepository.getParentPayments();
          emit(
            state.copyWith(
              data: state.data.copyWith(feeDues: feeDues, payments: payments),
            ),
          );
        case _ParentSection.notifications:
          final notifications = await _loadNotifications();
          emit(
            state.copyWith(
              data: state.data.copyWith(notifications: notifications),
            ),
          );
      }
      event.completer.complete();
    } on SessionExpiredException {
      onSessionExpired();
      event.completer.complete();
    } catch (error) {
      event.completer.completeError(error);
    }
  }
}
