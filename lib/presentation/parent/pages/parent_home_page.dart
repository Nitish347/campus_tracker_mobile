import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/demo_data.dart';
import '../../../domain/entities/parent_data.dart';
import '../../../domain/entities/student.dart';
import '../../auth/bloc/session_bloc.dart';
import '../../shared/ui_widgets.dart';
import '../bloc/parent_bloc.dart';

class ParentHomePage extends StatelessWidget {
  const ParentHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ParentBloc, ParentState>(
      builder: (context, state) {
        final pages = [
          _ParentDashboard(data: state.data),
          _TrackingView(data: state.data),
          const _FeeView(),
          const NotificationView(),
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
          body: pages[state.selectedIndex],
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

class _ParentDashboard extends StatelessWidget {
  const _ParentDashboard({required this.data});

  final ParentData data;

  @override
  Widget build(BuildContext context) {
    final assigned = data.students
        .where((student) => student.vehicle != 'Unassigned')
        .toList();
    final firstVehicle = data.vehicles.isNotEmpty
        ? data.vehicles.first
        : demoVehicles.first;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StatusHeader(
          title: 'Assigned vehicle',
          value: firstVehicle.id,
          subtitle: '${firstVehicle.route} - ${firstVehicle.driver}',
          icon: Icons.directions_bus,
        ),
        const SizedBox(height: 12),
        const SectionTitle(title: 'Student pickup and drop'),
        ...assigned.take(4).map((student) => PickupCard(student: student)),
        const SizedBox(height: 12),
        const SectionTitle(title: 'Payment'),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.payments)),
            title: const Text('Transport fee payment'),
            subtitle: const Text('Quarterly and half-yearly payment link'),
            trailing: FilledButton(
              onPressed: () =>
                  launchUrl(Uri.parse('https://example.com/payment')),
              child: const Text('Pay'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const SectionTitle(title: 'Fee reminder'),
        const Card(
          child: ListTile(
            leading: Icon(Icons.notifications_active),
            title: Text('Next fee due on 28 Jun'),
            subtitle: Text(
              'Reminder notification will be sent before due date.',
            ),
          ),
        ),
      ],
    );
  }
}

class PickupCard extends StatelessWidget {
  const PickupCard({super.key, required this.student});

  final Student student;

  @override
  Widget build(BuildContext context) {
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
                  Text('${student.className} - ${student.area}'),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                StatusChip(text: 'Picked 7:42 AM', color: Colors.green),
                SizedBox(height: 4),
                StatusChip(text: 'Drop pending', color: Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingView extends StatelessWidget {
  const _TrackingView({required this.data});

  final ParentData data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionTitle(title: 'Vehicle GPS location'),
        ...data.gps.map(
          (gps) => Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Color(0xff0f6b55)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          gps.alias?.isNotEmpty == true
                              ? '${gps.vehicleNo} - ${gps.alias}'
                              : gps.vehicleNo,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      StatusChip(
                        text: gps.ignition ? 'Ignition on' : 'Stopped',
                        color: gps.ignition ? Colors.green : Colors.grey,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InfoRow(label: 'Speed', value: '${gps.speed} km/h'),
                  InfoRow(
                    label: 'Latitude',
                    value: gps.latitude.toStringAsFixed(6),
                  ),
                  InfoRow(
                    label: 'Longitude',
                    value: gps.longitude.toStringAsFixed(6),
                  ),
                  InfoRow(
                    label: 'Odometer',
                    value: gps.odometer.toStringAsFixed(2),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.map),
                      label: const Text('Open in Maps'),
                      onPressed: () => launchUrl(
                        Uri.parse(
                          'https://maps.google.com/?q=${gps.latitude},${gps.longitude}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeeView extends StatelessWidget {
  const _FeeView();

  static const records = [
    ('Quarterly fee', 'Rs. 8,400', 'Pending'),
    ('Half-yearly fee', 'Rs. 16,200', 'Available'),
    ('Cash collection', 'Rs. 2,000', 'Collected'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const StatusHeader(
          title: 'Fee collection history',
          value: 'Rs. 26,600',
          subtitle: 'Total income and transport fee records',
          icon: Icons.account_balance_wallet,
        ),
        const SizedBox(height: 12),
        ...records.map(
          (record) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.receipt_long),
              title: Text(record.$1),
              subtitle: Text(record.$3),
              trailing: Text(
                record.$2,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class NotificationView extends StatelessWidget {
  const NotificationView({super.key});

  @override
  Widget build(BuildContext context) {
    final notices = [
      'Fee reminder notification sent',
      'BUS-04 route is running on time',
      'Driver uploaded pickup status',
      'Vehicle API live tracking enabled',
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: notices
          .map(
            (notice) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const Icon(Icons.notifications),
                title: Text(notice),
                subtitle: const Text('Just now'),
              ),
            ),
          )
          .toList(),
    );
  }
}
