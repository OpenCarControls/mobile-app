import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_car_app/config/theme_mode_config.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';

/// Holds the value loaded from SharedPreferences before [runApp].
/// Overridden in [ProviderScope] at app startup — never reads storage itself.
final initialThemeModeProvider = Provider<ThemeMode>((_) => ThemeMode.system);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(initialThemeModeProvider);

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await saveThemeMode(mode);
  }
}

/// The user's theme mode: follow the system, or always light or dark.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// The current vehicle's skin, or the default one when no vehicle is known
/// (the pairing wizard).
final currentSkinProvider = Provider<VehicleSkin>(
  (ref) => ref.watch(selectedVehicleProvider)?.skin ?? defaultSkin,
);
