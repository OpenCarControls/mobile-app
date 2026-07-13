import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/config/device_identity.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/screens/pairing_wizard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final (deviceId, isNew) = await getOrCreateDeviceId();
  dev.log(
    isNew ? 'Device ID created' : 'Device ID loaded',
    name: 'AppBootstrap',
  );

  // TEMPORARY: force a paired config for UI testing on Web
  final pairedConfig = kIsWeb
      ? const PairedVehicleConfig(
          vehicleId: 'opencar.cars.egmp.v1',
          bleRemoteId: '',
          transportPreference: TransportPreference.http,
        )
      : await PairedVehicleConfig.load();
  dev.log(
    pairedConfig != null
        ? 'Paired vehicle loaded: ${pairedConfig.vehicleId}'
        : 'No paired vehicle — wizard will be shown',
    name: 'AppBootstrap',
  );

  runApp(
    ProviderScope(
      overrides: [
        bleSourceDeviceIdProvider.overrideWithValue(deviceId),
        initialPairedVehicleConfigProvider.overrideWithValue(pairedConfig),
      ],
      child: const OpenCarApp(),
    ),
  );
}

class OpenCarApp extends StatelessWidget {
  const OpenCarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Open Car',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AppEntryRouter(),
    );
  }
}

/// Routes to [PairingWizardScreen] when no vehicle is paired, or directly
/// to the vehicle dashboard when one is. Reacts to [pairedVehicleProvider]
/// so unpairing from the dashboard automatically returns to the wizard.
class AppEntryRouter extends ConsumerWidget {
  const AppEntryRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(selectedVehicleProvider);
    if (vehicle == null) return const PairingWizardScreen();
    return vehicle.buildDashboard();
  }
}
