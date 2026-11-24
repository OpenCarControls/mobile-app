import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/can_bus_health_provider.dart';
import 'package:open_car_app/widgets/settings_rows.dart';

/// The CAN buses card of the settings: each bus's status as the device judges
/// it over the last few seconds, what it means, its frame rate and its error
/// counters since the device started. Needs a Bluetooth connection; shows a hint until the device
/// reports.
class CanBusHealthSection extends ConsumerWidget {
  const CanBusHealthSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buses = ref.watch(canBusHealthProvider);
    if (buses == null) {
      return const SettingsCard(
        children: [
          SettingsRow(
            title: 'CAN buses',
            subtitle: 'Waiting for the device to report its buses.',
          ),
        ],
      );
    }

    final ids = buses.keys.toList()..sort();
    return SettingsCard(
      children: [for (final id in ids) _busRow(id, buses[id]!)],
    );
  }

  Widget _busRow(int id, CanBusHealth health) {
    final hint = canBusStatusHint(health.status);
    return SettingsRow(
      title: health.listenOnly ? 'Bus $id (listen-only)' : 'Bus $id',
      value: canBusStatusLabel(health.status),
      subtitle: '$hint\n${canBusCounters(health)}',
    );
  }
}
