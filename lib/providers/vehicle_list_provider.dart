import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/models/vehicle_summary.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_summary_provider.dart';

/// A paired vehicle as the vehicle switcher and the Vehicles screen list it.
@immutable
class VehicleListEntry {
  const VehicleListEntry({
    required this.config,
    required this.name,
    required this.definition,
    required this.summary,
    required this.current,
  });

  final PairedVehicleConfig config;

  /// What to call it: the user's name, or else its platform's.
  final String name;

  /// Its platform; null when this build doesn't support it.
  final VehicleDefinition? definition;

  /// Its last known level, range and update, if any.
  final VehicleSummary? summary;

  /// Whether it is the current vehicle.
  final bool current;
}

/// Every paired vehicle, in the order they were paired.
final vehicleListProvider = Provider<List<VehicleListEntry>>((ref) {
  final paired = ref.watch(pairedVehiclesProvider);
  final summaries = ref.watch(vehicleSummariesProvider);
  final definitions = ref.watch(availableVehiclesProvider);
  return [
    for (final config in paired.vehicles)
      VehicleListEntry(
        config: config,
        name: pairedVehicleName(config, definitions),
        definition: definitions
            .where((d) => d.platformName == config.vehicleId)
            .firstOrNull,
        summary: summaries[config.storageKey],
        current: config.id == paired.currentId,
      ),
  ];
});
