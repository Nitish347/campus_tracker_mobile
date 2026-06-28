import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/demo_data.dart';
import '../../../domain/entities/student.dart';
import '../../../domain/repositories/campus_repository.dart';

abstract class DriverEvent {}

class DriverStarted extends DriverEvent {}

class DriverPicked extends DriverEvent {
  DriverPicked(this.studentId);
  final int studentId;
}

class DriverDropped extends DriverEvent {
  DriverDropped(this.studentId);
  final int studentId;
}

class DriverState {
  const DriverState({
    required this.loading,
    required this.students,
    required this.pickedAt,
    required this.droppedAt,
  });

  factory DriverState.initial() => const DriverState(
    loading: true,
    students: demoStudents,
    pickedAt: {},
    droppedAt: {},
  );

  final bool loading;
  final List<Student> students;
  final Map<int, DateTime> pickedAt;
  final Map<int, DateTime> droppedAt;

  DriverState copyWith({
    bool? loading,
    List<Student>? students,
    Map<int, DateTime>? pickedAt,
    Map<int, DateTime>? droppedAt,
  }) {
    return DriverState(
      loading: loading ?? this.loading,
      students: students ?? this.students,
      pickedAt: pickedAt ?? this.pickedAt,
      droppedAt: droppedAt ?? this.droppedAt,
    );
  }
}

class DriverBloc extends Bloc<DriverEvent, DriverState> {
  DriverBloc(this.campusRepository) : super(DriverState.initial()) {
    on<DriverStarted>(_started);
    on<DriverPicked>(_picked);
    on<DriverDropped>(_dropped);
  }

  final CampusRepository campusRepository;

  Future<void> _started(DriverStarted event, Emitter<DriverState> emit) async {
    final students = await campusRepository.getStudents();
    emit(state.copyWith(loading: false, students: students));
  }

  void _picked(DriverPicked event, Emitter<DriverState> emit) {
    final next = Map<int, DateTime>.from(state.pickedAt);
    next[event.studentId] = DateTime.now();
    emit(state.copyWith(pickedAt: next));
  }

  void _dropped(DriverDropped event, Emitter<DriverState> emit) {
    final next = Map<int, DateTime>.from(state.droppedAt);
    next[event.studentId] = DateTime.now();
    emit(state.copyWith(droppedAt: next));
  }
}
