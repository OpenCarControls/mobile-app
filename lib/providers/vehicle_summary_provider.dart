import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_car_app/config/vehicle_state_cache_config.dart';
import 'package:open_car_app/models/vehicle_summary.dart';

/// Holds the summaries loaded before [runApp]. Overridden in [ProviderScope] at
/// app startup; never reads storage itself.
final initialVehicleSummariesProvider = Provider<Map<String, VehicleSummary>>(
  (_) => const {},
);

/// Each paired vehicle's last known summary, by storage key, so the vehicle
/// lists can show it without a live link. Stored with the vehicle's cached
/// state, which [VehicleStateNotifier] writes.
class VehicleSummariesNotifier extends Notifier<Map<String, VehicleSummary>> {
  @override
  Map<String, VehicleSummary> build() =>
      ref.read(initialVehicleSummariesProvider);

  void update(String vehicleKey, VehicleSummary summary) =>
      state = {...state, vehicleKey: summary};

  /// Deletes the last known state of an unpaired vehicle.
  Future<void> forget(String vehicleKey) async {
    state = {...state}..remove(vehicleKey);
    await clearVehicleStateCache(vehicleKey);
  }
}

final vehicleSummariesProvider =
    NotifierProvider<VehicleSummariesNotifier, Map<String, VehicleSummary>>(
      VehicleSummariesNotifier.new,
    );
