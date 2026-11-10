import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_car_app/cars/virtual_car/virtual_car_definition.dart';
import 'package:open_car_app/cars/egmp/egmp_definition.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';

/// All vehicles supported by this build.
final availableVehiclesProvider = Provider<List<VehicleDefinition>>(
  (_) => const [EgmpDefinition(), VirtualCarDefinition()],
);

/// What to call [config]: the user's name, or else its platform's.
String pairedVehicleName(
  PairedVehicleConfig config,
  List<VehicleDefinition> definitions,
) {
  if (config.name != null) return config.name!;
  for (final definition in definitions) {
    if (definition.platformName == config.vehicleId) {
      return definition.displayName;
    }
  }
  return config.vehicleId;
}

/// What to call the current vehicle; null when none is paired.
final currentVehicleNameProvider = Provider<String?>((ref) {
  final config = ref.watch(pairedVehicleProvider);
  if (config == null) return null;
  return pairedVehicleName(config, ref.read(availableVehiclesProvider));
});

/// The current paired vehicle's definition, derived from [pairedVehicleProvider].
/// Null when no vehicle is paired, or when the stored vehicle isn't supported
/// by this build (the wizard is shown in both cases).
///
/// Read-only — set implicitly by pairing/unpairing via [pairedVehicleProvider].
final selectedVehicleProvider = Provider<VehicleDefinition?>((ref) {
  final config = ref.watch(pairedVehicleProvider);
  if (config == null) return null;
  final vehicles = ref.read(availableVehiclesProvider);
  for (final vehicle in vehicles) {
    if (vehicle.platformName == config.vehicleId) return vehicle;
  }
  return null;
});
