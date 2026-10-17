import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_car_app/cars/virtual_car/virtual_car_definition.dart';
import 'package:open_car_app/cars/egmp/egmp_definition.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';

/// All vehicles supported by this build.
final availableVehiclesProvider = Provider<List<VehicleDefinition>>(
  (_) => const [EgmpDefinition(), VirtualCarDefinition()],
);

/// The currently paired vehicle, derived from [pairedVehicleProvider].
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
