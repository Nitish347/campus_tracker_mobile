import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/entities/gps_point.dart';
import '../../../domain/entities/parent_data.dart';
import '../../../domain/entities/payment_record.dart';
import '../../../domain/entities/student.dart';
import '../../../domain/entities/fee_due.dart';
import '../../../domain/entities/transport_log.dart';
import '../../../domain/entities/vehicle.dart';
import '../../auth/bloc/session_bloc.dart';
import '../../shared/bus_route_map.dart';
import '../../shared/ui_widgets.dart';
import '../bloc/parent_bloc.dart';

const _schoolLocation = LatLng(26.9124, 75.7873);
const _jpisPaymentUrl =
    'https://paydirect.eduqfix.com/app/O5lzmbFZtNjrJqswwkPcNrkPSzC2HtendcnwR7jE/10857/34237';
const _jpsPaymentUrl =
    'https://paydirect.eduqfix.com/app/O5lzmbFZtNjrJqswwkPcNrkPSzC2HtendcnwR7jE/10857/34332';

// Runs a single-tab refresh (see ParentBloc's refreshHome/refreshTracking/etc)
// and surfaces any failure as a SnackBar instead of letting it propagate
// silently — used by every tab's RefreshIndicator.
Future<void> refreshParentSection(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Could not refresh: ${error.toString().replaceFirst('Exception: ', '')}',
        ),
      ),
    );
  }
}

class ParentHomePage extends StatelessWidget {
  const ParentHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ParentBloc, ParentState>(
      builder: (context, state) {
        final selected = _selectedStudent(state);
        final pages = [
          _ParentDashboard(data: state.data, selected: selected),
          _TrackingView(
            data: state.data,
            selected: selected,
            routeTrail: state.routeTrail,
          ),
          _HistoryView(data: state.data, selected: selected),
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
              ? _EmptyParentState(error: state.error)
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
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'History',
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
      height: 70,
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
    final totalDue = data.feeDues.fold<num>(
      0,
      (total, due) => total + due.balance,
    );
    final totalPaid = data.payments.fold<num>(
      0,
      (total, payment) => total + payment.amount,
    );
    final todayLogs = data.transportLogs.where(
      (log) => _isSameDay(log.recordedAt, DateTime.now()),
    );
    final pickedToday = todayLogs
        .where((log) => log.action == 'Pickup')
        .map((log) => log.studentId)
        .toSet()
        .length;
    final droppedToday = todayLogs
        .where((log) => log.action == 'Drop')
        .map((log) => log.studentId)
        .toSet()
        .length;
    final latestPayment = data.payments.isEmpty
        ? null
        : data.payments.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
    final latestLog = data.transportLogs.isEmpty
        ? null
        : data.transportLogs.reduce(
            (a, b) => a.recordedAt.isAfter(b.recordedAt) ? a : b,
          );
    final selectedDue = data.feeDues
        .where((due) => due.studentId == selected.id)
        .fold<num>(0, (total, due) => total + due.balance);
    final selectedPaid = data.payments
        .where((payment) => payment.studentId == selected.id)
        .fold<num>(0, (total, payment) => total + payment.amount);
    final selectedPickup = _todayLogForStudent(
      data.transportLogs,
      selected.id,
      'Pickup',
    );
    final selectedDrop = _todayLogForStudent(
      data.transportLogs,
      selected.id,
      'Drop',
    );
    return RefreshIndicator(
      onRefresh: () => refreshParentSection(
        context,
        () => context.read<ParentBloc>().refreshHome(),
      ),
      child: ListView(
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
            childrenCount: data.students.length,
            totalDue: totalDue,
            totalPaid: totalPaid,
            pickedToday: pickedToday,
            droppedToday: droppedToday,
          ),
          const SizedBox(height: 12),
          AppSection(
            title: 'Selected child summary',
            subtitle: 'Live route, fee, and attendance status',
            child: Column(
              children: [
                InfoRow(label: 'Route', value: selected.route),
                InfoRow(
                  label: 'Vehicle',
                  value: vehicle?.id ?? selected.vehicle,
                ),
                InfoRow(
                  label: 'Driver',
                  value: vehicle?.driver ?? 'Unassigned',
                ),
                InfoRow(label: 'Fee due', value: _money(selectedDue)),
                InfoRow(label: 'Paid total', value: _money(selectedPaid)),
                InfoRow(
                  label: 'Pickup today',
                  value: selectedPickup == null
                      ? 'Not recorded'
                      : timeLabel(selectedPickup.recordedAt),
                ),
                InfoRow(
                  label: 'Drop today',
                  value: selectedDrop == null
                      ? 'Not recorded'
                      : timeLabel(selectedDrop.recordedAt),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSection(
            title: 'Today pickup and drop',
            subtitle: 'Child-wise transport status and assigned vehicle',
            child: Column(
              children: data.students.map((student) {
                final childVehicle = _vehicleForStudent(data, student);
                return PickupCard(
                  student: student,
                  vehicle: childVehicle,
                  pickup: _todayLogForStudent(
                    data.transportLogs,
                    student.id,
                    'Pickup',
                  ),
                  drop: _todayLogForStudent(
                    data.transportLogs,
                    student.id,
                    'Drop',
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          AppSection(
            title: 'Latest updates',
            subtitle: 'Most recent backend records for this account',
            child: Column(
              children: [
                DataTile(
                  icon: Icons.receipt_long,
                  title: latestPayment == null
                      ? 'No payment recorded'
                      : '${_money(latestPayment.amount)} paid',
                  subtitle: latestPayment == null
                      ? 'Admin payment records will appear here.'
                      : '${latestPayment.student} • ${_dateLabel(latestPayment.date)} • ${latestPayment.method}',
                  color: Colors.green,
                ),
                DataTile(
                  icon: Icons.location_on,
                  title: latestLog == null
                      ? 'No pickup/drop log yet'
                      : '${latestLog.action} recorded',
                  subtitle: latestLog == null
                      ? 'Driver GPS logs will appear after pickup/drop.'
                      : '${_studentName(data.students, latestLog.studentId)} • ${_dateLabel(latestLog.recordedAt)} ${timeLabel(latestLog.recordedAt)}',
                  color: Colors.blue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSection(
            title: 'Fee reminder',
            subtitle: 'Real dues calculated from generated fee records',
            child: _FeeReminderCard(feeDues: data.feeDues),
          ),
        ],
      ),
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({
    required this.vehicle,
    required this.childrenCount,
    required this.totalDue,
    required this.totalPaid,
    required this.pickedToday,
    required this.droppedToday,
  });

  final Vehicle? vehicle;
  final int childrenCount;
  final num totalDue;
  final num totalPaid;
  final int pickedToday;
  final int droppedToday;

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
          icon: Icons.family_restroom,
          label: 'Children',
          value: '$childrenCount',
          color: Colors.blue,
        ),
        AppMetricCard(
          icon: Icons.directions_bus,
          label: 'Vehicle',
          value: vehicle?.id ?? 'Not assigned',
          color: Colors.green,
        ),
        AppMetricCard(
          icon: Icons.login,
          label: 'Picked today',
          value: '$pickedToday/$childrenCount',
          color: Colors.orange,
        ),
        AppMetricCard(
          icon: Icons.account_balance_wallet,
          label: totalDue > 0 ? 'Total dues' : 'Paid',
          value: totalDue > 0 ? _money(totalDue) : _money(totalPaid),
          color: Colors.red,
        ),
      ],
    );
  }
}

class PickupCard extends StatelessWidget {
  const PickupCard({
    super.key,
    required this.student,
    required this.vehicle,
    required this.pickup,
    required this.drop,
  });

  final Student student;
  final Vehicle? vehicle;
  final TransportLog? pickup;
  final TransportLog? drop;

  @override
  Widget build(BuildContext context) {
    final moving = vehicle?.status == 'On route';
    final complete = pickup != null && drop != null;
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
                  text: complete
                      ? 'Complete'
                      : pickup != null
                      ? 'Picked'
                      : moving
                      ? 'On route'
                      : vehicle?.status ?? 'Waiting',
                  color: complete || pickup != null
                      ? Colors.green
                      : moving
                      ? Colors.blue
                      : Colors.orange,
                ),
                const SizedBox(height: 4),
                StatusChip(
                  text: drop == null
                      ? 'Drop pending'
                      : 'Dropped ${timeLabel(drop!.recordedAt)}',
                  color: drop == null ? Colors.orange : Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingView extends StatelessWidget {
  const _TrackingView({
    required this.data,
    required this.selected,
    required this.routeTrail,
  });

  final ParentData data;
  final Student selected;
  final List<GpsPoint> routeTrail;

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

    return RefreshIndicator(
      onRefresh: () => refreshParentSection(
        context,
        () => context.read<ParentBloc>().refreshTracking(),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionTitle(title: 'Live vehicle map'),
          BusRouteMap(
            focus: selectedPosition,
            subject: selected.id,
            markers: markers,
            trail: [
              for (final point in routeTrail)
                LatLng(point.latitude, point.longitude),
            ],
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
                      const Icon(
                        Icons.directions_bus,
                        color: Color(0xff0f6b55),
                      ),
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
                        color: gps?.ignition == true
                            ? Colors.green
                            : Colors.grey,
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
      ),
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView({required this.data, required this.selected});

  final ParentData data;
  final Student selected;

  @override
  Widget build(BuildContext context) {
    final history = _historyForStudent(data, selected);
    return RefreshIndicator(
      onRefresh: () => refreshParentSection(
        context,
        () => context.read<ParentBloc>().refreshHistory(),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StatusHeader(
            title: 'Child travel history',
            value: selected.name,
            subtitle: 'Date-wise check-in and check-out with location',
            icon: Icons.history,
          ),
          const SizedBox(height: 12),
          if (history.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('No check-in or check-out history found yet.'),
              ),
            ),
          ...history.map((day) => _HistoryDayCard(day: day)),
        ],
      ),
    );
  }
}

class _HistoryDayCard extends StatelessWidget {
  const _HistoryDayCard({required this.day});

  final _StudentHistoryDay day;

  @override
  Widget build(BuildContext context) {
    final complete = day.checkIn != null && day.checkOut != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event_available, color: Color(0xff0f6b55)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _dateLabel(day.date),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                StatusChip(
                  text: complete ? 'Complete' : 'Partial',
                  color: complete ? Colors.green : Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (day.checkIn != null)
              _HistoryLocationRow(label: 'Check-in', log: day.checkIn!),
            if (day.checkIn != null && day.checkOut != null)
              const SizedBox(height: 8),
            if (day.checkOut != null)
              _HistoryLocationRow(label: 'Check-out', log: day.checkOut!),
          ],
        ),
      ),
    );
  }
}

class _HistoryLocationRow extends StatelessWidget {
  const _HistoryLocationRow({required this.label, required this.log});

  final String label;
  final TransportLog log;

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
              '$label ${timeLabel(log.recordedAt)}\n${_logCoords(log)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Open location',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => launchUrl(
              Uri.parse(
                'https://maps.google.com/?q=${log.latitude},${log.longitude}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeeView extends StatelessWidget {
  const _FeeView({required this.data, required this.selected});

  final ParentData data;
  final Student selected;

  @override
  Widget build(BuildContext context) {
    final totalDue = data.feeDues.fold<num>(
      0,
      (total, due) => total + due.balance,
    );
    final totalPaid = data.feeDues.fold<num>(
      0,
      (total, due) => total + due.paidAmount,
    );
    final receivedPayments = data.payments.fold<num>(
      0,
      (total, payment) => total + payment.amount,
    );
    final totalBilled = data.feeDues.fold<num>(
      0,
      (total, due) => total + due.billed,
    );
    return RefreshIndicator(
      onRefresh: () => refreshParentSection(
        context,
        () => context.read<ParentBloc>().refreshFees(),
      ),
      child: ListView(
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
          _PayFeesSection(branch: branchForPayment(data.students)),
          const SizedBox(height: 12),
          AppSection(
            title: 'Account summary',
            subtitle: 'Total billing, paid amount, and pending balance',
            child: Column(
              children: [
                InfoRow(label: 'Total billed', value: _money(totalBilled)),
                InfoRow(
                  label: 'Paid / received',
                  value: _money(totalPaid > 0 ? totalPaid : receivedPayments),
                ),
                InfoRow(label: 'Total dues', value: _money(totalDue)),
                InfoRow(
                  label: 'Payment records',
                  value: '${data.payments.length}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSection(
            title: 'Payment records',
            subtitle: 'Date, receipt, method, and amount paid',
            child: data.payments.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('No payment records found yet.'),
                  )
                : Column(
                    children: data.payments
                        .map((payment) => _PaymentRecordTile(payment: payment))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 12),
          AppSection(
            title: 'Student fee details',
            subtitle: 'Month-wise dues and paid amount for each child',
            child: Column(
              children: data.students.map((student) {
                final dues = data.feeDues
                    .where((due) => due.studentId == student.id)
                    .toList();
                final payments = data.payments
                    .where((payment) => payment.studentId == student.id)
                    .toList();
                return _StudentFeeCard(
                  student: student,
                  dues: dues,
                  payments: payments,
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          AppSection(
            title: 'Last update',
            subtitle: 'Latest fee status from admin records',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
              title: Text(_lastPaymentLabel(data.payments, selected)),
              subtitle: Text(
                'Fee information is updated after admin records a collection.',
              ),
              trailing: StatusChip(
                text: totalDue > 0 ? 'Due' : 'Clear',
                color: totalDue > 0 ? Colors.orange : Colors.green,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentFeeCard extends StatelessWidget {
  const _StudentFeeCard({
    required this.student,
    required this.dues,
    required this.payments,
  });

  final Student student;
  final List<FeeDue> dues;
  final List<PaymentRecord> payments;

  @override
  Widget build(BuildContext context) {
    final due = dues.fold<num>(0, (sum, item) => sum + item.balance);
    final paidFromDues = dues.fold<num>(
      0,
      (sum, item) => sum + item.paidAmount,
    );
    final paidFromPayments = payments.fold<num>(
      0,
      (sum, item) => sum + item.amount,
    );
    final paid = paidFromDues > 0 ? paidFromDues : paidFromPayments;
    final billed = dues.fold<num>(0, (sum, item) => sum + item.billed);
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
            InfoRow(label: 'Total billed', value: _money(billed)),
            InfoRow(label: 'Total paid', value: _money(paid)),
            InfoRow(label: 'Total dues', value: _money(due)),
            if (dues.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('No generated dues found for this child.'),
              )
            else
              ...dues.map((item) => _DueRecordTile(due: item)),
          ],
        ),
      ),
    );
  }
}

class _PaymentRecordTile extends StatelessWidget {
  const _PaymentRecordTile({required this.payment});

  final PaymentRecord payment;

  @override
  Widget build(BuildContext context) {
    return DataTile(
      icon: Icons.receipt_long,
      title: '${_dateLabel(payment.date)} - ${_money(payment.amount)}',
      subtitle:
          '${payment.student} • ${payment.method} • Receipt ${payment.id}',
      color: Colors.green,
      trailing: StatusChip(
        text: payment.status.isEmpty ? 'Paid' : payment.status,
        color: Colors.green,
      ),
    );
  }
}

class _DueRecordTile extends StatelessWidget {
  const _DueRecordTile({required this.due});

  final FeeDue due;

  @override
  Widget build(BuildContext context) {
    final clear = due.balance <= 0 || due.status == 'Paid';
    return DataTile(
      icon: clear ? Icons.check_circle : Icons.pending_actions,
      title: '${due.month} • ${due.status}',
      subtitle: 'Billed ${_money(due.billed)} • Paid ${_money(due.paidAmount)}',
      color: clear ? Colors.green : Colors.orange,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Due', style: TextStyle(color: Colors.black54)),
          Text(
            _money(due.balance),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _FeeReminderCard extends StatelessWidget {
  const _FeeReminderCard({required this.feeDues});

  final List<FeeDue> feeDues;

  @override
  Widget build(BuildContext context) {
    final dueCount = feeDues.where((due) => due.balance > 0).length;
    final totalDue = feeDues.fold<num>(0, (sum, due) => sum + due.balance);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.notifications_active),
        title: Text(
          dueCount == 0
              ? 'No pending fee reminders'
              : '$dueCount due record${dueCount == 1 ? '' : 's'} pending',
        ),
        subtitle: Text(
          dueCount == 0
              ? 'All generated transport dues are clear.'
              : '${_money(totalDue)} total balance pending.',
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
    final notifications = data.notifications;
    return RefreshIndicator(
      onRefresh: () => refreshParentSection(
        context,
        () => context.read<ParentBloc>().refreshNotifications(),
      ),
      child: notifications.isEmpty
          ? _buildTips(context)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: notifications.map((item) {
                final style = _styleFor(item.type);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: style.color.withValues(alpha: .12),
                      child: Icon(style.icon, color: style.color),
                    ),
                    title: Text(
                      item.title,
                      style: TextStyle(
                        fontWeight: item.read
                            ? FontWeight.w600
                            : FontWeight.w900,
                      ),
                    ),
                    subtitle: Text(item.body),
                    trailing: Text(
                      _timeAgo(item.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black45,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }

  ({IconData icon, Color color}) _styleFor(String type) {
    switch (type) {
      case 'Pickup':
        return (icon: Icons.login, color: Colors.green);
      case 'Drop':
        return (icon: Icons.logout, color: Colors.blue);
      case 'FeeReminder':
        return (icon: Icons.payments, color: Colors.orange);
      default:
        return (icon: Icons.notifications, color: Colors.purple);
    }
  }

  Widget _buildTips(BuildContext context) {
    final vehicle = _vehicleForStudent(data, selected);
    final notices = [
      _Notice(
        Icons.directions_bus,
        '${selected.vehicle} ${vehicle?.status.toLowerCase() ?? 'assigned'}',
        '${selected.name} is linked to ${selected.route}.',
        Colors.green,
      ),
      _Notice(
        Icons.security,
        'Pickup and drop alerts enabled',
        'You will get a notification here when the driver picks up or drops your child.',
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
  const _EmptyParentState({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasError ? Icons.error_outline : Icons.family_restroom,
              size: 40,
              color: hasError ? Colors.red : Colors.black45,
            ),
            const SizedBox(height: 12),
            Text(
              hasError
                  ? 'Could not load your data: $error'
                  : 'No students are linked to this parent phone number.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: hasError ? Colors.red : null,
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    context.read<ParentBloc>().add(ParentRefreshed()),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
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
      branch: '',
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

class _StudentHistoryDay {
  _StudentHistoryDay(this.date);

  final DateTime date;
  TransportLog? checkIn;
  TransportLog? checkOut;
}

List<_StudentHistoryDay> _historyForStudent(ParentData data, Student student) {
  final days = <String, _StudentHistoryDay>{};
  for (final log in data.transportLogs.where(
    (log) => log.studentId == student.id,
  )) {
    final date = DateTime(
      log.recordedAt.year,
      log.recordedAt.month,
      log.recordedAt.day,
    );
    final key = _dateKey(log.recordedAt);
    final day = days.putIfAbsent(key, () => _StudentHistoryDay(date));
    if (log.action == 'Pickup') {
      if (day.checkIn == null ||
          log.recordedAt.isBefore(day.checkIn!.recordedAt)) {
        day.checkIn = log;
      }
    } else if (log.action == 'Drop') {
      if (day.checkOut == null ||
          log.recordedAt.isAfter(day.checkOut!.recordedAt)) {
        day.checkOut = log;
      }
    }
  }
  return days.values.toList()..sort((a, b) => b.date.compareTo(a.date));
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

String _logCoords(TransportLog log) {
  return '${log.latitude.toStringAsFixed(6)}, ${log.longitude.toStringAsFixed(6)}'
      ' - +/-${log.accuracy.toStringAsFixed(0)}m';
}

String _money(num value) {
  final rounded = value.round();
  final text = rounded.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{2})+\d$)'),
    (match) => '${match[1]},',
  );
  return 'Rs. $text';
}

String _lastPaymentLabel(List<PaymentRecord> payments, Student selected) {
  final rows = payments.where((payment) => payment.studentId == selected.id);
  if (rows.isEmpty) return '${selected.name} - no payment recorded yet';
  final latest = rows.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
  return '${selected.name} paid ${_money(latest.amount)} on ${_dateLabel(latest.date)}';
}

TransportLog? _todayLogForStudent(
  List<TransportLog> logs,
  int studentId,
  String action,
) {
  final today = DateTime.now();
  final rows = logs.where(
    (log) =>
        log.studentId == studentId &&
        log.action == action &&
        _isSameDay(log.recordedAt, today),
  );
  if (rows.isEmpty) return null;
  return rows.reduce(
    (a, b) => action == 'Pickup'
        ? a.recordedAt.isBefore(b.recordedAt)
              ? a
              : b
        : a.recordedAt.isAfter(b.recordedAt)
        ? a
        : b,
  );
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _studentName(List<Student> students, int studentId) {
  for (final student in students) {
    if (student.id == studentId) return student.name;
  }
  return 'Student #$studentId';
}

String _timeAgo(DateTime value) {
  final seconds = DateTime.now().difference(value).inSeconds.abs();
  if (seconds < 60) return '${seconds}s ago';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ago';
  return '${minutes ~/ 60}h ago';
}

/// The branch to bill against, taken from the children on this account.
///
/// Empty when it is unset, or when siblings are recorded against different
/// branches -- sending a parent to one school's portal because a sibling
/// attends it would be worse than asking them to call the office.
@visibleForTesting
String branchForPayment(List<Student> students) {
  final branches = students
      .map((student) => student.branch.trim().toUpperCase())
      .where((branch) => branch.isNotEmpty)
      .toSet();
  return branches.length == 1 ? branches.first : '';
}

/// Shows the one payment portal belonging to this family's school.
///
/// The admin sets the branch per student. With none set there is no way to
/// know which school is owed the money, so no button is offered at all --
/// guessing would send a parent to the wrong portal.
class _PayFeesSection extends StatelessWidget {
  const _PayFeesSection({required this.branch});

  final String branch;

  @override
  Widget build(BuildContext context) {
    final url = branch == 'JPIS'
        ? _jpisPaymentUrl
        : branch == 'JPS'
            ? _jpsPaymentUrl
            : null;

    if (url == null) {
      return AppSection(
        title: 'Pay fees online',
        subtitle: 'Not available yet',
        child: Text(
          'Online payment is not set up for your child\'s account yet. '
          'Please contact the school transport office.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return AppSection(
      title: 'Pay fees online',
      subtitle: 'Opens the school\'s secure payment portal in your browser',
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: Text('Pay fees - $branch'),
          onPressed: () => launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          ),
        ),
      ),
    );
  }
}
