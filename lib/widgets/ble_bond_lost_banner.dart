import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/providers/ble_connection_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/screens/help_screen.dart';

/// Shown when the device keeps dropping the BLE link right after connecting:
/// it most likely no longer has this phone's bond (removed from the device,
/// or its flash erased), and Android, still holding the old keys, shows no
/// pairing prompt. Unpairing returns to the pairing wizard, which can only
/// find the device in pairing mode: Help explains how to get it there.
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
        'Bluetooth settings, put the device in pairing mode (see Help), then '
        'pair again.',
      ),
      actions: [
        TextButton(
          onPressed: () => HelpScreen.open(context),
          child: const Text('Help'),
        ),
        TextButton(
          onPressed: () => ref.read(pairedVehicleProvider.notifier).unpair(),
          child: const Text('Unpair and pair again'),
        ),
      ],
    );
  }
}
