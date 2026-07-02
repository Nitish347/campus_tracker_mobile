import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/entities/gps_point.dart';
import '../../../domain/entities/parent_data.dart';
import '../../../domain/entities/student.dart';
import '../../../domain/entities/vehicle.dart';
import '../../auth/bloc/session_bloc.dart';
import '../../shared/ui_widgets.dart';
import '../bloc/parent_bloc.dart';

const _schoolLocation = LatLng(26.9124, 75.7873);

class ParentHomePage extends StatelessWidget {
  const ParentHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ParentBloc, ParentState>(
      builder: (context, state) {
        final selected = _selectedStudent(state);
        final pages = [
          _ParentDashboard(data: state.data, selected: selected),
          _TrackingView(data: state.data, selected: selected),
          _FeeView(data: state.data, selected: selected),
          NotificationView(data: state.data, selected: selected),
        ];
        return Scaffold(
          appBar: AppBar(
            title: const Text('Parent App'),
            actions: [
              if (state.loading)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                onPressed: () =>
                    context.read<ParentBloc>().add(ParentRefreshed()),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                onPressed: () =>
                    context.read<SessionBloc>().add(SessionLoggedOut()),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: state.data.students.isEmpty
              ? const _EmptyParentState()
              : Column(
                  children: [
                    _ChildSelector(state: state),
                    Expanded(child: pages[state.selectedIndex]),
                  ],
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: state.selectedIndex,
            onDestinationSelected: (value) =>
                context.read<ParentBloc>().add(ParentTabChanged(value)),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.location_on_outlined),
                selectedIcon: Icon(Icons.location_on),
                label: 'Track',
              ),
              NavigationDestination(
                icon: Icon(Icons.payments_outlined),
                selectedIcon: Icon(Icons.payments),
                label: 'Fees',
              ),
              NavigationDestination(
                icon: Icon(Icons.notifications_outlined),
                selectedIcon: Icon(Icons.notifications),
                label: 'Alerts',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChildSelector extends StatelessWidget {
  const _ChildSelector({required this.state});

  final ParentState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      height:70,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: state.data.students.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final student = state.data.students[index];
          final selected = student.id == state.selectedStudentId;
          return ChoiceChip(
            selected: selected,
            showCheckmark: false,
            avatar: CircleAvatar(
              child: Text(
                student.name
                    .split(' ')
                    .where((part) => part.isNotEmpty)
                    .map((part) => part[0])
                    .take(2)
                    .join(),
              ),
            ),
            label: SizedBox(
              width: 140,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${student.className} - ${student.vehicle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            onSelected: (_) => context.read<ParentBloc>().add(
              ParentStudentSelected(student.id),
            ),
          );
        },
      ),
    );
  }
}

class _ParentDashboard extends StatelessWidget {
  const _ParentDashboard({required this.data, required this.selected});

  final ParentData data;
  final Student selected;

  @override
  Widget build(BuildContext context) {
    final vehicle = _vehicleForStudent(data, selected);
    final gps = _gpsForStudent(data, selected);
    final due = data.students.fold<num>(
      0,
      (total, student) => total + student.monthlyDue,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StatusHeader(
          title: 'Selected child',
          value: selected.name,
          subtitle: '${selected.className} - ${selected.area}',
          icon: Icons.school,
        ),
        const SizedBox(height: 12),
        _QuickStats(
          vehicle: vehicle,
          gps: gps,
          childrenCount: data.students.length,
          totalDue: due,
        ),
        const SizedBox(height: 12),
        const SectionTitle(title: 'Today pickup and drop'),
        ...data.students.map((student) {
          final childVehicle = _vehicleForStudent(data, student);
          return PickupCard(student: student, vehicle: childVehicle);
        }),
        const SizedBox(height: 12),
        const SectionTitle(title: 'Fee reminder'),
        _FeeReminderCard(students: data.students),
      ],
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({
    required this.vehicle,
    required this.gps,
    required this.childrenCount,
    required this.totalDue,
  });

  final Vehicle? vehicle;
  final GpsPoint? gps;
  final int childrenCount;
  final num totalDue;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: [
        _MetricCard(
          icon: Icons.family_restroom,
          label: 'Children',
          value: '$childrenCount',
          color: Colors.blue,
        ),
        _MetricCard(
          icon: Icons.directions_bus,
          label: 'Vehicle',
          value: vehicle?.id ?? 'Not assigned',
          color: Colors.green,
        ),
        _MetricCard(
          icon: Icons.speed,
          label: 'Speed',
          value: '${gps?.speed ?? vehicle?.speed ?? 0} km/h',
          color: Colors.orange,
        ),
        _MetricCard(
          icon: Icons.account_balance_wallet,
          label: 'Due',
          value: _money(totalDue),
          color: Colors.red,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color),
            Text(label, style: const TextStyle(color: Colors.black54)),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class PickupCard extends StatelessWidget {
  const PickupCard({super.key, required this.student, required this.vehicle});

  final Student student;
  final Vehicle? vehicle;

  @override
  Widget build(BuildContext context) {
    final moving = vehicle?.status == 'On route';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.school)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text('${student.route} - ${student.area}'),
                  Text(
                    vehicle == null
                        ? 'Vehicle not assigned'
                        : '${vehicle!.id} - ${vehicle!.driver}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusChip(
                  text: moving ? 'On route' : vehicle?.status ?? 'Waiting',
                  color: moving ? Colors.green : Colors.orange,
                ),
                const SizedBox(height: 4),
                const StatusChip(text: 'Drop pending', color: Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingView extends StatelessWidget {
  const _TrackingView({required this.data, required this.selected});

  final ParentData data;
  final Student selected;

  @override
  Widget build(BuildContext context) {
    final vehicle = _vehicleForStudent(data, selected);
    final gps = _gpsForStudent(data, selected);
    final selectedPosition = _positionForStudent(data, selected);
    final markers = data.students.map((student) {
      final point = _positionForStudent(data, student);
      return Marker(
        markerId: MarkerId(student.vehicle),
        position: point,
        infoWindow: InfoWindow(
          title: student.vehicle,
          snippet: '${student.name} - ${student.route}',
        ),
        icon: student.id == selected.id
            ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
            : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      );
    }).toSet();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(title: 'Live vehicle map'),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 360,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: selectedPosition,
                zoom: 14,
              ),
              markers: markers,
              mapToolbarEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.directions_bus, color: Color(0xff0f6b55)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        vehicle?.id ?? selected.vehicle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    StatusChip(
                      text: gps?.ignition == true
                          ? 'Moving'
                          : vehicle?.status ?? 'Live',
                      color: gps?.ignition == true ? Colors.green : Colors.grey,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InfoRow(label: 'Route', value: selected.route),
                InfoRow(
                  label: 'Driver',
                  value: vehicle?.driver ?? 'Unassigned',
                ),
                InfoRow(
                  label: 'Speed',
                  value: '${gps?.speed ?? vehicle?.speed ?? 0} km/h',
                ),
                InfoRow(
                  label: 'Updated',
                  value: gps == null
                      ? 'Demo location'
                      : _timeAgo(gps.timestamp),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.map),
                    label: const Text('Open in Google Maps'),
                    onPressed: () => launchUrl(
                      Uri.parse(
                        'https://maps.google.com/?q=${selectedPosition.latitude},${selectedPosition.longitude}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FeeView extends StatelessWidget {
  const _FeeView({required this.data, required this.selected});

  final ParentData data;
  final Student selected;

  @override
  Widget build(BuildContext context) {
    final totalDue = data.students.fold<num>(
      0,
      (total, student) => total + student.monthlyDue,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StatusHeader(
          title: 'Transport fee due',
          value: _money(totalDue),
          subtitle:
              '${data.students.length} child account${data.students.length == 1 ? '' : 's'} linked',
          icon: Icons.account_balance_wallet,
        ),
        const SizedBox(height: 12),
        const SectionTitle(title: 'Student fee details'),
        ...data.students.map((student) => _StudentFeeCard(student: student)),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
            title: const Text('Last payment'),
            subtitle: Text(
              '${selected.name} - receipt will appear after collection',
            ),
            trailing: const StatusChip(text: 'Pending', color: Colors.orange),
          ),
        ),
      ],
    );
  }
}

class _StudentFeeCard extends StatelessWidget {
  const _StudentFeeCard({required this.student});

  final Student student;

  @override
  Widget build(BuildContext context) {
    final due = student.monthlyDue;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.school)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text('${student.route} - ${student.vehicle}'),
                    ],
                  ),
                ),
                Text(
                  _money(due),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: due > 0
                    ? () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Payment request queued for ${student.name}',
                          ),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.payments),
                label: Text(due > 0 ? 'Pay now' : 'No dues'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeeReminderCard extends StatelessWidget {
  const _FeeReminderCard({required this.students});

  final List<Student> students;

  @override
  Widget build(BuildContext context) {
    final dueCount = students.where((student) => student.monthlyDue > 0).length;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.notifications_active),
        title: Text(
          dueCount == 0
              ? 'No pending fee reminders'
              : '$dueCount fee reminder${dueCount == 1 ? '' : 's'} active',
        ),
        subtitle: const Text(
          'Monthly transport fee is generated from the assigned route.',
        ),
      ),
    );
  }
}

class NotificationView extends StatelessWidget {
  const NotificationView({
    super.key,
    required this.data,
    required this.selected,
  });

  final ParentData data;
  final Student selected;

  @override
  Widget build(BuildContext context) {
    final vehicle = _vehicleForStudent(data, selected);
    final notices = [
      _Notice(
        Icons.directions_bus,
        '${selected.vehicle} ${vehicle?.status.toLowerCase() ?? 'assigned'}',
        '${selected.name} is linked to ${selected.route}.',
        Colors.green,
      ),
      _Notice(
        Icons.payments,
        selected.monthlyDue > 0
            ? '${_money(selected.monthlyDue)} transport fee pending'
            : 'No fee due',
        'Monthly route fee is updated from admin payments.',
        Colors.orange,
      ),
      _Notice(
        Icons.security,
        'Pickup and drop alerts enabled',
        'You will see driver status updates here.',
        Colors.blue,
      ),
      _Notice(
        Icons.location_on,
        'Live map enabled',
        'Bus location is available on the Track tab.',
        Colors.purple,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: notices
          .map(
            (notice) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: notice.color.withValues(alpha: .12),
                  child: Icon(notice.icon, color: notice.color),
                ),
                title: Text(notice.title),
                subtitle: Text(notice.subtitle),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _Notice {
  const _Notice(this.icon, this.title, this.subtitle, this.color);

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
}

class _EmptyParentState extends StatelessWidget {
  const _EmptyParentState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No students are linked to this parent phone number.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

Student _selectedStudent(ParentState state) {
  if (state.data.students.isEmpty) {
    return const Student(
      id: 0,
      name: 'Student',
      regNo: '-',
      className: '-',
      phone: '',
      secondaryPhone: '',
      vehicle: 'Unassigned',
      area: '-',
      route: '-',
      monthlyDue: 0,
    );
  }
  return state.data.students.firstWhere(
    (student) => student.id == state.selectedStudentId,
    orElse: () => state.data.students.first,
  );
}

Vehicle? _vehicleForStudent(ParentData data, Student student) {
  for (final vehicle in data.vehicles) {
    if (vehicle.id == student.vehicle || vehicle.route == student.route) {
      return vehicle;
    }
  }
  return null;
}

GpsPoint? _gpsForStudent(ParentData data, Student student) {
  for (final gps in data.gps) {
    if (gps.vehicleNo == student.vehicle || gps.alias == student.route) {
      return gps;
    }
  }
  return null;
}

LatLng _positionForStudent(ParentData data, Student student) {
  final gps = _gpsForStudent(data, student);
  if (gps != null) return LatLng(gps.latitude, gps.longitude);

  final vehicle = _vehicleForStudent(data, student);
  if (vehicle == null) return _schoolLocation;

  return LatLng(
    _schoolLocation.latitude + ((50 - vehicle.y.toDouble()) * 0.002),
    _schoolLocation.longitude + ((vehicle.x.toDouble() - 50) * 0.002),
  );
}

String _money(num value) {
  final rounded = value.round();
  final text = rounded.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{2})+\d$)'),
    (match) => '${match[1]},',
  );
  return 'Rs. $text';
}

String _timeAgo(DateTime value) {
  final seconds = DateTime.now().difference(value).inSeconds.abs();
  if (seconds < 60) return '${seconds}s ago';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ago';
  return '${minutes ~/ 60}h ago';
}
