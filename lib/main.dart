import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/cars/egmp/licenses.dart';
import 'package:open_car_app/config/button_style_config.dart';
import 'package:open_car_app/config/device_identity.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/config/saved_layouts_config.dart';
import 'package:open_car_app/config/theme_mode_config.dart';
import 'package:open_car_app/config/unsupported_commands_config.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/dashboard_layout_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/theme_provider.dart';
import 'package:open_car_app/screens/dashboard/dashboard_screen.dart';
import 'package:open_car_app/screens/pairing_wizard_screen.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/licenses.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerEgmpLicenses();
  registerThemeLicenses();

  final (deviceId, isNew) = await getOrCreateDeviceId();
  dev.log(
    isNew ? 'Device ID created' : 'Device ID loaded',
    name: 'AppBootstrap',
  );

  final pairedConfig = await PairedVehicleConfig.load();
  dev.log(
    pairedConfig != null
        ? 'Paired vehicle loaded: ${pairedConfig.vehicleId}'
        : 'No paired vehicle — wizard will be shown',
    name: 'AppBootstrap',
  );

  final themeMode = await loadThemeMode();
  final buttonStyle = await loadButtonStyle();
  final savedLayouts = await loadSavedLayouts();
  final unsupportedCommands = await loadUnsupportedCommands();

  runApp(
    ProviderScope(
      overrides: [
        bleSourceDeviceIdProvider.overrideWithValue(deviceId),
        initialPairedVehicleConfigProvider.overrideWithValue(pairedConfig),
        initialThemeModeProvider.overrideWithValue(themeMode),
        initialButtonStyleProvider.overrideWithValue(buttonStyle),
        initialSavedLayoutsProvider.overrideWithValue(savedLayouts),
        initialUnsupportedCommandsProvider.overrideWithValue(
          unsupportedCommands,
        ),
      ],
      child: const OpenCarApp(),
    ),
  );
}

class OpenCarApp extends ConsumerWidget {
  const OpenCarApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(currentSkinProvider);
    return MaterialApp(
      title: 'Open Car',
      themeMode: ref.watch(themeModeProvider),
      theme: buildAppTheme(skin, Brightness.light),
      darkTheme: buildAppTheme(skin, Brightness.dark),
      home: const AppEntryRouter(),
    );
  }
}

/// Routes to [PairingWizardScreen] when no vehicle is paired, or directly
/// to the [DashboardScreen] when one is. Reacts to [pairedVehicleProvider]
/// so unpairing from the dashboard automatically returns to the wizard.
class AppEntryRouter extends ConsumerWidget {
  const AppEntryRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(selectedVehicleProvider);
    if (vehicle == null) return const PairingWizardScreen();
    return const DashboardScreen();
  }
}
