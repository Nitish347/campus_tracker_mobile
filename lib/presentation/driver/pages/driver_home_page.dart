import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/entities/gps_point.dart';
import '../../../domain/entities/student.dart';
import '../../../domain/entities/vehicle.dart';
import '../../auth/bloc/session_bloc.dart';
import '../../shared/bus_route_map.dart';
import '../../shared/ui_widgets.dart';
import '../bloc/driver_bloc.dart';

const _schoolLocation = LatLng(26.9124, 75.7873);

class DriverHomePage extends StatelessWidget {
  const DriverHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DriverBloc, DriverState>(
      listenWhen: (previous, current) =>
          previous.error != current.error || previous.notice != current.notice,
      listener: (context, state) {
        final message = state.error ?? state.notice;
        if (message == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: state.error == null ? null : Colors.red,
          ),
        );
      },
      builder: (context, state) {
        final pages = [
          _DriverDashboard(state: state),
          _AssignedStudentsView(state: state),
          _DriverMapView(state: state),
          _DriverActivityView(state: state),
        ];
        return Scaffold(
          appBar: AppBar(
            title: const Text('Driver App'),
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
                    context.read<DriverBloc>().add(DriverRefreshed()),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                onPressed: () =>
                    context.read<SessionBloc>().add(SessionLoggedOut()),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: pages[state.selectedIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: state.selectedIndex,
            onDestinationSelected: (value) =>
                context.read<DriverBloc>().add(DriverTabChanged(value)),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Duty',
              ),
              NavigationDestination(
                icon: Icon(Icons.groups_outlined),
                selectedIcon: Icon(Icons.groups),
                label: 'Students',
              ),
              NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: 'Map',
              ),
              NavigationDestination(
                icon: Icon(Icons.fact_check_outlined),
                selectedIcon: Icon(Icons.fact_check),
                label: 'Logs',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DriverDashboard extends StatelessWidget {
  const _DriverDashboard({required this.state});

  final DriverState state;

  @override
  Widget build(BuildContext context) {
    final vehicle = state.vehicle;
    return RefreshIndicator(
      onRefresh: () => context.read<DriverBloc>().refreshData(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StatusHeader(
            title: 'Route duty',
            value: vehicle?.id ?? state.driver?.vehicle ?? 'Vehicle',
            subtitle:
                '${state.driver?.name ?? 'Driver'} - ${vehicle?.route ?? state.driver?.route ?? 'Route'}',
            icon: Icons.drive_eta,
          ),
          const SizedBox(height: 12),
          _DutyActions(state: state),
          const SizedBox(height: 12),
          _DriverStats(state: state),
          const SizedBox(height: 12),
          AppSection(
            title: 'Route progress',
            subtitle: 'Live duty summary for today',
            child: Column(
              children: [
                InfoRow(
                  label: 'Assigned students',
                  value: '${state.students.length}',
                ),
                InfoRow(label: 'Picked', value: '${state.pickedCount}'),
                InfoRow(label: 'Dropped', value: '${state.droppedCount}'),
                InfoRow(
                  label: 'Vehicle status',
                  value: vehicle?.status ?? 'Waiting',
                ),
                InfoRow(
                  label: 'Current speed',
                  value: '${state.gps?.speed ?? vehicle?.speed ?? 0} km/h',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSection(
            title: 'Quick notification',
            subtitle: 'Send simple route updates from the bus',
            child: _NotificationActions(state: state),
          ),
        ],
      ),
    );
  }
}

class _DutyActions extends StatelessWidget {
  const _DutyActions({required this.state});

  final DriverState state;

  @override
  Widget build(BuildContext context) {
    final checkIn = state.todayCheckIn;
    final checkOut = state.todayCheckOut;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_searching, color: Color(0xff0f6b55)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    state.dutyStarted ? 'Duty is active' : 'Duty not active',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                StatusChip(
                  text: state.dutyStarted ? 'Checked in' : 'Standby',
                  color: state.dutyStarted ? Colors.green : Colors.orange,
                ),
              ],
            ),
            if (checkIn != null) ...[
              const SizedBox(height: 10),
              _GeoLine(label: 'Check-in', record: checkIn),
            ],
            if (checkOut != null) ...[
              const SizedBox(height: 8),
              _GeoLine(label: 'Check-out', record: checkOut),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: checkIn == null || checkOut != null
                        ? () => context.read<DriverBloc>().add(
                            DriverDutyCheckedIn(),
                          )
                        : null,
                    icon: const Icon(Icons.login),
                    label: const Text('Check in'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: checkIn != null && checkOut == null
                        ? () => context.read<DriverBloc>().add(
                            DriverDutyCheckedOut(),
                          )
                        : null,
                    icon: const Icon(Icons.logout),
                    label: const Text('Check out'),
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

class _DriverStats extends StatelessWidget {
  const _DriverStats({required this.state});

  final DriverState state;

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
        AppMetricCard(
          icon: Icons.groups,
          label: 'Students',
          value: '${state.students.length}',
          color: Colors.blue,
        ),
        AppMetricCard(
          icon: Icons.login,
          label: 'Picked',
          value: '${state.pickedCount}',
          color: Colors.green,
        ),
        AppMetricCard(
          icon: Icons.logout,
          label: 'Dropped',
          value: '${state.droppedCount}',
          color: Colors.orange,
        ),
        AppMetricCard(
          icon: Icons.speed,
          label: 'Speed',
          value: '${state.gps?.speed ?? state.vehicle?.speed ?? 0} km/h',
          color: Colors.purple,
        ),
      ],
    );
  }
}

class _AssignedStudentsView extends StatelessWidget {
  const _AssignedStudentsView({required this.state});

  final DriverState state;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => context.read<DriverBloc>().refreshData(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppSection(
            title: 'Today\'s students',
            subtitle: 'Pickup and drop actions with GPS proof',
            child: Column(
              children: [
                if (state.students.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(4),
                    child: Text('No students assigned to this driver route.'),
                  ),
                ...state.students.map((student) {
                  final pickedAt = _todayRecord(state.pickedAt[student.id]);
                  final droppedAt = _todayRecord(state.droppedAt[student.id]);
                  return DriverStudentCard(
                    student: student,
                    pickedAt: pickedAt,
                    droppedAt: droppedAt,
                    onPicked: () => context.read<DriverBloc>().add(
                      DriverPicked(student.id),
                    ),
                    onDropped: () => context.read<DriverBloc>().add(
                      DriverDropped(student.id),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
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
  final DriverGeoRecord? pickedAt;
  final DriverGeoRecord? droppedAt;
  final VoidCallback onPicked;
  final VoidCallback onDropped;

  @override
  Widget build(BuildContext context) {
    final complete = pickedAt != null && droppedAt != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    student.name
                        .split(' ')
                        .where((part) => part.isNotEmpty)
                        .map((part) => part[0])
                        .take(2)
                        .join(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text('${student.className} - ${student.area}'),
                      Text(
                        '${student.vehicle} - ${student.route}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  text: complete
                      ? 'Done'
                      : pickedAt != null
                      ? 'Picked'
                      : 'Waiting',
                  color: complete
                      ? Colors.green
                      : pickedAt != null
                      ? Colors.blue
                      : Colors.orange,
                ),
              ],
            ),
            if (pickedAt != null) ...[
              const SizedBox(height: 10),
              _GeoLine(label: 'Pickup', record: pickedAt!),
            ],
            if (droppedAt != null) ...[
              const SizedBox(height: 8),
              _GeoLine(label: 'Drop', record: droppedAt!),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: pickedAt == null ? onPicked : null,
                    icon: const Icon(Icons.login),
                    label: Text(pickedAt == null ? 'Pickup' : 'Picked'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: pickedAt != null && droppedAt == null
                        ? onDropped
                        : null,
                    icon: const Icon(Icons.logout),
                    label: Text(droppedAt == null ? 'Drop' : 'Dropped'),
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

class _DriverMapView extends StatelessWidget {
  const _DriverMapView({required this.state});

  final DriverState state;

  @override
  Widget build(BuildContext context) {
    final gps = state.gps;
    final busPosition = _vehiclePosition(state.vehicle, gps);

    return RefreshIndicator(
      onRefresh: () => context.read<DriverBloc>().refreshData(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle(title: 'Route map'),
          BusRouteMap(
            focus: busPosition,
            height: 390,
            zoom: 13.5,
            trail: [
              for (final point in state.routeTrail)
                LatLng(point.latitude, point.longitude),
            ],
            markers: {
              const Marker(
                markerId: MarkerId('school'),
                position: _schoolLocation,
                infoWindow: InfoWindow(title: 'School'),
              ),
              // No bus pin without a real GPS fix: a guessed position looks
              // exactly like a real one on the map.
              if (gps != null)
                Marker(
                  markerId: MarkerId(state.vehicle?.id ?? 'vehicle'),
                  position: busPosition,
                  infoWindow: InfoWindow(
                    title: state.vehicle?.id ?? 'Vehicle',
                    snippet: state.vehicle?.route ?? state.driver?.route,
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen,
                  ),
                ),
            },
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  InfoRow(label: 'Vehicle', value: state.vehicle?.id ?? '-'),
                  InfoRow(
                    label: 'Route',
                    value: state.vehicle?.route ?? state.driver?.route ?? '-',
                  ),
                  InfoRow(label: 'Driver', value: state.driver?.name ?? '-'),
                  InfoRow(
                    label: 'Speed',
                    value:
                        '${state.gps?.speed ?? state.vehicle?.speed ?? 0} km/h',
                  ),
                  InfoRow(
                    label: 'Updated',
                    value: state.gps == null
                        ? 'No GPS position yet'
                        : timeLabel(state.gps!.timestamp),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.map),
                      label: const Text('Open in Google Maps'),
                      onPressed: () => launchUrl(
                        Uri.parse(
                          'https://maps.google.com/?q=${busPosition.latitude},${busPosition.longitude}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverActivityView extends StatelessWidget {
  const _DriverActivityView({required this.state});

  final DriverState state;

  @override
  Widget build(BuildContext context) {
    final logDays = _buildLogDays(state);

    return RefreshIndicator(
      onRefresh: () => context.read<DriverBloc>().refreshData(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle(title: 'GPS activity log'),
          if (logDays.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No check-in, pickup, or drop records yet.'),
              ),
            ),
          ...logDays.expand(
            (day) => [
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: Text(
                  _dateLabel(day.date),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xff0f6b55),
                  ),
                ),
              ),
              if (day.checkIn != null || day.checkOut != null)
                _DutyLogCard(checkIn: day.checkIn, checkOut: day.checkOut),
              ...day.students.map((log) => _StudentLogCard(log: log)),
            ],
          ),
          const SizedBox(height: 12),
          const SectionTitle(title: 'Driver notifications'),
          _NotificationActions(state: state),
        ],
      ),
    );
  }
}

class _NotificationActions extends StatelessWidget {
  const _NotificationActions({required this.state});

  final DriverState state;

  @override
  Widget build(BuildContext context) {
    final messages = [
      'Route started for ${state.vehicle?.id ?? state.driver?.vehicle ?? 'vehicle'}',
      'Pickup running on time',
      'Route delayed by 10 minutes',
      'Drop completed for all marked students',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: messages
              .map(
                (message) => ActionChip(
                  avatar: const Icon(Icons.campaign, size: 18),
                  label: Text(message),
                  onPressed: () => context.read<DriverBloc>().add(
                    DriverNoticeSent('Notification queued: $message'),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _GeoLine extends StatelessWidget {
  const _GeoLine({required this.label, required this.record});

  final String label;
  final DriverGeoRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xfff3f7f5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xffdfe8e4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.my_location, size: 18, color: Color(0xff0f6b55)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label ${timeLabel(record.time)}\n${_coords(record)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _DutyLogCard extends StatelessWidget {
  const _DutyLogCard({required this.checkIn, required this.checkOut});

  final DriverGeoRecord? checkIn;
  final DriverGeoRecord? checkOut;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.drive_eta, color: Color(0xff0f6b55)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Driver duty',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (checkIn != null) _GeoLine(label: 'Check-in', record: checkIn!),
            if (checkIn != null && checkOut != null) const SizedBox(height: 8),
            if (checkOut != null)
              _GeoLine(label: 'Check-out', record: checkOut!),
          ],
        ),
      ),
    );
  }
}

class _StudentLogCard extends StatelessWidget {
  const _StudentLogCard({required this.log});

  final _StudentDayLog log;

  @override
  Widget build(BuildContext context) {
    final complete = log.pickedAt != null && log.droppedAt != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text(_initials(log.student.name))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.student.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text('${log.student.className} - ${log.student.area}'),
                    ],
                  ),
                ),
                StatusChip(
                  text: complete
                      ? 'Complete'
                      : log.pickedAt != null
                      ? 'Picked'
                      : 'Drop only',
                  color: complete
                      ? Colors.green
                      : log.pickedAt != null
                      ? Colors.blue
                      : Colors.orange,
                ),
              ],
            ),
            if (log.pickedAt != null) ...[
              const SizedBox(height: 10),
              _GeoLine(label: 'Pickup', record: log.pickedAt!),
            ],
            if (log.droppedAt != null) ...[
              const SizedBox(height: 8),
              _GeoLine(label: 'Drop', record: log.droppedAt!),
            ],
          ],
        ),
      ),
    );
  }
}

class _LogDay {
  _LogDay(this.date);

  final DateTime date;
  DriverGeoRecord? checkIn;
  DriverGeoRecord? checkOut;
  final Map<int, _StudentDayLog> studentsById = {};

  List<_StudentDayLog> get students {
    final rows = studentsById.values.toList()
      ..sort((a, b) => a.student.name.compareTo(b.student.name));
    return rows;
  }
}

class _StudentDayLog {
  _StudentDayLog(this.student);

  final Student student;
  DriverGeoRecord? pickedAt;
  DriverGeoRecord? droppedAt;
}

List<_LogDay> _buildLogDays(DriverState state) {
  final days = <String, _LogDay>{};

  _LogDay dayFor(DriverGeoRecord record) {
    final date = DateTime(record.time.year, record.time.month, record.time.day);
    return days.putIfAbsent(_dateKey(record.time), () => _LogDay(date));
  }

  if (state.checkIn != null) {
    dayFor(state.checkIn!).checkIn = state.checkIn;
  }
  if (state.checkOut != null) {
    dayFor(state.checkOut!).checkOut = state.checkOut;
  }

  for (final student in state.students) {
    final pickedAt = state.pickedAt[student.id];
    final droppedAt = state.droppedAt[student.id];
    if (pickedAt != null) {
      dayFor(pickedAt).studentsById
              .putIfAbsent(student.id, () => _StudentDayLog(student))
              .pickedAt =
          pickedAt;
    }
    if (droppedAt != null) {
      dayFor(droppedAt).studentsById
              .putIfAbsent(student.id, () => _StudentDayLog(student))
              .droppedAt =
          droppedAt;
    }
  }

  return days.values.toList()..sort((a, b) => b.date.compareTo(a.date));
}

DriverGeoRecord? _todayRecord(DriverGeoRecord? record) {
  if (record == null) return null;
  final now = DateTime.now();
  if (record.time.year != now.year ||
      record.time.month != now.month ||
      record.time.day != now.day) {
    return null;
  }
  return record;
}

String _dateKey(DateTime value) {
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

String _dateLabel(DateTime value) {
  final now = DateTime.now();
  final date = DateTime(value.year, value.month, value.day);
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final suffix = date == today
      ? 'Today'
      : date == yesterday
      ? 'Yesterday'
      : null;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final text = '${value.day} ${months[value.month - 1]} ${value.year}';
  return suffix == null ? text : '$suffix - $text';
}

String _initials(String name) {
  final initials = name
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0])
      .take(2)
      .join();
  return initials.isEmpty ? 'ST' : initials;
}

LatLng _vehiclePosition(Vehicle? vehicle, GpsPoint? gps) {
  if (gps != null) return LatLng(gps.latitude, gps.longitude);
  if (vehicle == null) return _schoolLocation;
  return LatLng(
    _schoolLocation.latitude + ((50 - vehicle.y.toDouble()) * 0.002),
    _schoolLocation.longitude + ((vehicle.x.toDouble() - 50) * 0.002),
  );
}

String _coords(DriverGeoRecord record) {
  return '${record.latitude.toStringAsFixed(6)}, ${record.longitude.toStringAsFixed(6)}'
      ' - +/-${record.accuracy.toStringAsFixed(0)}m';
}
