import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/demo_data.dart';
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

class ParentState {
  const ParentState({
    required this.loading,
    required this.selectedIndex,
    required this.data,
    required this.selectedStudentId,
  });

  factory ParentState.initial() => ParentState(
    loading: true,
    selectedIndex: 0,
    data: ParentData(
      vehicles: demoVehicles,
      students: demoStudents,
      gps: demoGps,
    ),
    selectedStudentId: demoStudents.first.id,
  );

  final bool loading;
  final int selectedIndex;
  final ParentData data;
  final int selectedStudentId;

  ParentState copyWith({
    bool? loading,
    int? selectedIndex,
    ParentData? data,
    int? selectedStudentId,
  }) {
    return ParentState(
      loading: loading ?? this.loading,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      data: data ?? this.data,
      selectedStudentId: selectedStudentId ?? this.selectedStudentId,
    );
  }
}

class ParentBloc extends Bloc<ParentEvent, ParentState> {
  ParentBloc(this.campusRepository, {required this.parentPhone})
    : super(ParentState.initial()) {
    on<ParentStarted>(_load);
    on<ParentRefreshed>(_load);
    on<ParentTabChanged>(
      (event, emit) => emit(state.copyWith(selectedIndex: event.index)),
    );
    on<ParentStudentSelected>(
      (event, emit) => emit(state.copyWith(selectedStudentId: event.studentId)),
    );
  }

  final CampusRepository campusRepository;
  final String parentPhone;

  Future<void> _load(ParentEvent event, Emitter<ParentState> emit) async {
    emit(state.copyWith(loading: true));
    final vehicles = await campusRepository.getVehicles();
    final students = await campusRepository.getStudents();
    final gps = await campusRepository.getGpsPoints();
    final phone = _onlyDigits(parentPhone);
    final children = students
        .where(
          (student) =>
              _onlyDigits(student.phone) == phone ||
              _onlyDigits(student.secondaryPhone) == phone,
        )
        .toList();
    final visibleStudents = children.isEmpty ? students : children;
    final selectedExists = visibleStudents.any(
      (student) => student.id == state.selectedStudentId,
    );
    emit(
      state.copyWith(
        loading: false,
        selectedStudentId: selectedExists
            ? state.selectedStudentId
            : visibleStudents.firstOrNull?.id ?? 0,
        data: ParentData(
          vehicles: vehicles,
          students: visibleStudents,
          gps: gps,
        ),
      ),
    );
  }
}

String _onlyDigits(String value) => value.replaceAll(RegExp(r'\D'), '');
