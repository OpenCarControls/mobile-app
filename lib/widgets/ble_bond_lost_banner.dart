import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/providers/ble_connection_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';

/// Shown when the device keeps dropping the BLE link right after connecting:
/// it most likely no longer has this phone's bond (removed from the device,
/// or its flash erased), and Android, still holding the old keys, shows no
/// pairing prompt. Unpairing returns to the pairing wizard.
class BleBondLostBanner extends ConsumerWidget {
  const BleBondLostBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(bleBondLostProvider)) return const SizedBox.shrink();

    return MaterialBanner(
      leading: const Icon(Icons.bluetooth_disabled),
      content: const Text(
        'The vehicle keeps dropping the connection, so this phone is probably '
        'no longer paired with it. Forget the OpenCar device in Android\'s '
        'Bluetooth settings, then pair again.',
      ),
      actions: [
        TextButton(
          onPressed: () => ref.read(pairedVehicleProvider.notifier).unpair(),
          child: const Text('Unpair and pair again'),
        ),
      ],
    );
  }
}
