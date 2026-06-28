import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/student.dart';
import '../../auth/bloc/session_bloc.dart';
import '../../shared/ui_widgets.dart';
import '../bloc/driver_bloc.dart';

class DriverHomePage extends StatelessWidget {
  const DriverHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DriverBloc, DriverState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Driver App'),
            actions: [
              IconButton(
                onPressed: () =>
                    context.read<SessionBloc>().add(SessionLoggedOut()),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const StatusHeader(
                title: 'Route duty',
                value: 'Pickup and drop',
                subtitle: 'Mark picked and dropped with timestamp',
                icon: Icons.drive_eta,
              ),
              const SizedBox(height: 12),
              const SectionTitle(title: 'Assigned students'),
              if (state.loading) const LinearProgressIndicator(),
              ...state.students.map(
                (student) => DriverStudentCard(
                  student: student,
                  pickedAt: state.pickedAt[student.id],
                  droppedAt: state.droppedAt[student.id],
                  onPicked: () =>
                      context.read<DriverBloc>().add(DriverPicked(student.id)),
                  onDropped: () =>
                      context.read<DriverBloc>().add(DriverDropped(student.id)),
                ),
              ),
              const SizedBox(height: 12),
              const SectionTitle(title: 'Notification'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.campaign),
                  title: const Text('Notify parents'),
                  subtitle: const Text(
                    'Route delay, pickup complete, drop complete',
                  ),
                  trailing: FilledButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Notification queued')),
                    ),
                    child: const Text('Send'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const SectionTitle(title: 'Upload work'),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.cloud_upload),
                  title: Text('Play Store, App Store and Web upload work'),
                  subtitle: Text('Marked as client-side publishing work'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class DriverStudentCard extends StatelessWidget {
  const DriverStudentCard({
    super.key,
    required this.student,
    required this.pickedAt,
    required this.droppedAt,
    required this.onPicked,
    required this.onDropped,
  });

  final Student student;
  final DateTime? pickedAt;
  final DateTime? droppedAt;
  final VoidCallback onPicked;
  final VoidCallback onDropped;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text('${student.area} - ${student.phone}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (pickedAt != null) Text('Picked at ${timeLabel(pickedAt!)}'),
            if (droppedAt != null) Text('Dropped at ${timeLabel(droppedAt!)}'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: pickedAt == null ? onPicked : null,
                    icon: const Icon(Icons.login),
                    label: Text(pickedAt == null ? 'Mark picked' : 'Picked'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: droppedAt == null ? onDropped : null,
                    icon: const Icon(Icons.logout),
                    label: Text(droppedAt == null ? 'Mark drop' : 'Dropped'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
