import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

/// Shown when the device reports a `platform_id` that doesn't match the paired
/// vehicle (e.g. its firmware was reflashed for another platform). The device's
/// messages are ignored meanwhile; the user decides whether to re-pair.
class PlatformMismatchBanner extends ConsumerWidget {
  const PlatformMismatchBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mismatchedId = ref.watch(
      vehicleStateProvider.select((s) => s.mismatchedPlatformId),
    );
    if (mismatchedId == null) return const SizedBox.shrink();

    final hexId = mismatchedId.toRadixString(16).toUpperCase().padLeft(8, '0');
    return MaterialBanner(
      leading: const Icon(Icons.warning_amber),
      content: Text(
        'The device reports a different vehicle platform (0x$hexId) than the '
        'one paired. Its updates are ignored until you re-pair.',
      ),
      actions: [
        TextButton(
          onPressed: () => ref.read(pairedVehicleProvider.notifier).unpair(),
          child: const Text('Unpair'),
        ),
      ],
    );
  }
}
