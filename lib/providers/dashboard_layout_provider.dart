import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_car_app/config/saved_layouts_config.dart';
import 'package:open_car_app/models/dashboard_layout.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';

/// Holds the layouts loaded before [runApp]. Overridden in [ProviderScope] at
/// app startup; never reads storage itself.
final initialSavedLayoutsProvider = Provider<SavedLayouts>((_) => const {});

/// The user's layouts, by [savedLayoutKey].
class SavedLayoutsNotifier extends Notifier<SavedLayouts> {
  @override
  SavedLayouts build() => ref.read(initialSavedLayoutsProvider);

  /// Saves [layout] for [grid] on the current vehicle.
  void save(DashboardGrid grid, List<TileLayoutEntry> layout) {
    final key = _key(grid);
    if (key == null) return;
    state = {...state, key: layout};
    unawaited(saveLayout(key, layout));
  }

  /// Puts [grid] back to the platform's default on the current vehicle.
  void reset(DashboardGrid grid) {
    final key = _key(grid);
    if (key == null) return;
    state = {...state}..remove(key);
    unawaited(clearLayout(key));
  }

  /// Puts every grid back to the platform's default on the current vehicle.
  void resetAll() => DashboardGrid.values.forEach(reset);

  /// Deletes the layouts of an unpaired vehicle.
  Future<void> forget(String vehicleKey) async {
    final keys = [
      for (final grid in DashboardGrid.values) savedLayoutKey(vehicleKey, grid),
    ];
    state = {...state}..removeWhere((key, _) => keys.contains(key));
    await Future.wait(keys.map(clearLayout));
  }

  String? _key(DashboardGrid grid) {
    final vehicleKey = ref.read(pairedVehicleProvider)?.storageKey;
    return vehicleKey == null ? null : savedLayoutKey(vehicleKey, grid);
  }
}

final savedLayoutsProvider =
    NotifierProvider<SavedLayoutsNotifier, SavedLayouts>(
      SavedLayoutsNotifier.new,
    );

/// The layout of [tier]'s grid on the current vehicle: the user's, or the
/// platform's default when they haven't changed it.
final dashboardLayoutProvider =
    Provider.family<List<TileLayoutEntry>, DashboardTier>((ref, tier) {
      final vehicle = ref.watch(selectedVehicleProvider);
      if (vehicle == null) return const [];
      final vehicleKey = ref.watch(pairedVehicleProvider)?.storageKey;
      final saved = vehicleKey == null
          ? null
          : ref.watch(savedLayoutsProvider)[savedLayoutKey(
              vehicleKey,
              DashboardGrid.of(tier),
            )];
      return saved == null
          ? vehicle.defaultLayout(tier)
          : sanitizeLayout(saved, vehicle, tier);
    });
