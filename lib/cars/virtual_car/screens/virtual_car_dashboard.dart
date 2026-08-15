import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/cars/virtual_car/constants.g.dart';
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/providers/ble_connection_provider.dart';
import 'package:open_car_app/transport/http_transport.dart';

class VirtualCarDashboardScreen extends ConsumerWidget {
  const VirtualCarDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(vehicleStateProvider);
    final transportType = ref.watch(transportTypeProvider);
    final isBle =
        transportType == TransportType.ble ||
        transportType == TransportType.stub ||
        transportType == TransportType.http;
    final showAdvanced = isBle && snapshot.isAdvancedStateLive;
    final awaitingAdvanced = isBle && !snapshot.isAdvancedStateLive;

    final basic = snapshot.basicState as BasicState;
    final advanced = snapshot.advancedState as AdvancedState;
    final system = snapshot.system;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Open Car'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              kPlatformName,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'simulate') {
                final transport = ref.read(carTransportProvider);
                if (transport is HttpCarTransport) {
                  try {
                    await transport.simulate();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Simulation error: $e')),
                      );
                    }
                  }
                }
              } else if (value == 'unpair') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Unpair vehicle?'),
                    content: const Text(
                      'This will remove the pairing and return you to the '
                      'setup wizard. The vehicle will also forget this phone '
                      '(factory reset required to re-pair).',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Unpair'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref.read(pairedVehicleProvider.notifier).unpair();
                  // AppEntryRouter will rebuild to show the wizard.
                }
              }
            },
            itemBuilder: (_) => [
              if (transportType == TransportType.http)
                const PopupMenuItem(
                  value: 'simulate',
                  child: ListTile(
                    leading: Icon(Icons.bug_report),
                    title: Text('Toggle Simulation'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'unpair',
                child: ListTile(
                  leading: Icon(Icons.link_off),
                  title: Text('Unpair vehicle'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (transportType == TransportType.ble) {
            ref.read(bleConnectionProvider.notifier).forceReconnect();
            // Add a small delay so the refresh animation shows.
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // ── Basic state ─────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: _SectionHeader(title: 'State')),
              _StateHeaderSuffix(
                lastUpdated: snapshot.lastUpdated,
                awaitingAdvanced: awaitingAdvanced,
                isStateLive: snapshot.isStateLive,
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _StateTile(
                label: 'Odometer',
                value: '${basic.odometer} km',
                icon: Icons.straighten,
              ),
              _StateTile(
                label: 'Driving',
                value: basic.isDriving ? 'Yes' : 'No',
                icon: Icons.directions_car,
              ),
            ],
          ),

          // ── Advanced state (BLE only, shown once live data arrives) ────────
          if (showAdvanced) ...[
            const SizedBox(height: 16),
            _SectionHeader(title: 'Advanced State'),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                _StateTile(
                  label: 'Speed',
                  value: '${advanced.speed} kph',
                  icon: Icons.speed,
                ),
                _StateTile(
                  label: 'Gear',
                  value: _gearLabel(advanced.gear),
                  icon: Icons.settings_input_component,
                ),
              ],
            ),
          ],

          // ── Basic controls ───────────────────────────────────────────────
          const SizedBox(height: 24),
          _SectionHeader(title: 'Controls'),
          const SizedBox(height: 8),
          _DoorLockCard(
            locked: basic.areDoorsLocked,
            onToggle: () {
              ref
                  .read(vehicleStateProvider.notifier)
                  .sendBasicCommand(
                    BasicCommand(
                      doorLock: DoorLockCommand(lock: !basic.areDoorsLocked),
                    ).writeToBuffer(),
                  );
            },
          ),

          // ── Advanced controls (BLE only, shown once live data arrives) ────
          if (showAdvanced) ...[
            const SizedBox(height: 16),
            _SectionHeader(title: 'Advanced Controls'),
            const SizedBox(height: 8),
            _CustomState1Card(
              enabled: advanced.customState1,
              onToggle: () {
                ref
                    .read(vehicleStateProvider.notifier)
                    .sendAdvancedCommand(
                      AdvancedCommand(
                        toggleCustomState1: ToggleCustomState1Command(),
                      ).writeToBuffer(),
                    );
              },
            ),
          ],

          // ── System info ──────────────────────────────────────────────────
          if (system != null) ...[
            const SizedBox(height: 24),
            _SystemInfoRow(
              firmwareVersion: system.firmwareVersion,
              hardwareType: system.hardwareType,
            ),
          ],
        ],
      ),
      ),
    );
  }

  static String _gearLabel(AdvancedState_Gear gear) {
    final name = gear.name;
    const prefix = 'GEAR_';
    if (name.startsWith(prefix)) return name.substring(prefix.length);
    return name;
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

/// Formats a UTC [DateTime] as a local-time string, e.g. "31 May, 14:23:05".
String _formatTimestamp(DateTime dt) {
  final local = dt.toLocal();
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
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  final s = local.second.toString().padLeft(2, '0');
  return '${local.day} ${months[local.month - 1]}, $h:$m:$s';
}

/// Displays a spinner and/or "Updated …" timestamp to the right of a section
/// header. The timestamp is hidden while the state is live.
class _StateHeaderSuffix extends StatelessWidget {
  final DateTime? lastUpdated;
  final bool awaitingAdvanced;
  final bool isStateLive;

  const _StateHeaderSuffix({
    required this.lastUpdated,
    required this.awaitingAdvanced,
    required this.isStateLive,
  });

  @override
  Widget build(BuildContext context) {
    final showTimestamp = !isStateLive;
    if (!awaitingAdvanced && !showTimestamp) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (awaitingAdvanced)
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        if (showTimestamp && lastUpdated != null) ...[
          if (awaitingAdvanced) const SizedBox(width: 6),
          Text(
            'Updated ${_formatTimestamp(lastUpdated!)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

class _StateTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StateTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

class _DoorLockCard extends StatelessWidget {
  final bool locked;
  final VoidCallback onToggle;

  const _DoorLockCard({required this.locked, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              locked ? Icons.lock : Icons.lock_open,
              color: locked ? colorScheme.primary : colorScheme.outline,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Doors',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    locked ? 'Locked' : 'Unlocked',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onToggle,
              child: Text(locked ? 'Unlock' : 'Lock'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomState1Card extends StatelessWidget {
  final bool enabled;
  final VoidCallback onToggle;

  const _CustomState1Card({required this.enabled, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              enabled ? Icons.toggle_on : Icons.toggle_off,
              color: enabled ? colorScheme.primary : colorScheme.outline,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Custom State 1',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    enabled ? 'On' : 'Off',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onToggle,
              child: Text(enabled ? 'Turn Off' : 'Turn On'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemInfoRow extends StatelessWidget {
  final String firmwareVersion;
  final String hardwareType;

  const _SystemInfoRow({
    required this.firmwareVersion,
    required this.hardwareType,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      'Firmware: $firmwareVersion  •  Hardware: $hardwareType',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
