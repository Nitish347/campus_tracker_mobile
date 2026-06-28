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

class ParentState {
  const ParentState({
    required this.loading,
    required this.selectedIndex,
    required this.data,
  });

  factory ParentState.initial() => ParentState(
    loading: true,
    selectedIndex: 0,
    data: ParentData(
      vehicles: demoVehicles,
      students: demoStudents,
      gps: demoGps,
    ),
  );

  final bool loading;
  final int selectedIndex;
  final ParentData data;

  ParentState copyWith({bool? loading, int? selectedIndex, ParentData? data}) {
    return ParentState(
      loading: loading ?? this.loading,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      data: data ?? this.data,
    );
  }
}

class ParentBloc extends Bloc<ParentEvent, ParentState> {
  ParentBloc(this.campusRepository) : super(ParentState.initial()) {
    on<ParentStarted>(_load);
    on<ParentRefreshed>(_load);
    on<ParentTabChanged>(
      (event, emit) => emit(state.copyWith(selectedIndex: event.index)),
    );
  }

  final CampusRepository campusRepository;

  Future<void> _load(ParentEvent event, Emitter<ParentState> emit) async {
    emit(state.copyWith(loading: true));
    final vehicles = await campusRepository.getVehicles();
    final students = await campusRepository.getStudents();
    final gps = await campusRepository.getGpsPoints();
    emit(
      state.copyWith(
        loading: false,
        data: ParentData(vehicles: vehicles, students: students, gps: gps),
      ),
    );
  }
}
