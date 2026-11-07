import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

/// Made-up states for the debug gallery.
List<({String name, VehicleSnapshot snapshot})> virtualCarSamples() => [
  (
    name: 'Parked',
    snapshot: VehicleSnapshot(
      basicState: BasicState(
        odometer: 1234,
        isDriving: false,
        areDoorsLocked: true,
      ),
      advancedState: AdvancedState(
        speed: 0,
        gear: AdvancedState_Gear.GEAR_PARK,
        customState1: false,
      ),
      isStateLive: true,
      isAdvancedStateLive: true,
    ),
  ),
  (
    name: 'Driving',
    snapshot: VehicleSnapshot(
      basicState: BasicState(
        odometer: 1240,
        isDriving: true,
        areDoorsLocked: false,
      ),
      advancedState: AdvancedState(
        speed: 72,
        gear: AdvancedState_Gear.GEAR_DRIVE,
        customState1: true,
      ),
      isStateLive: true,
      isAdvancedStateLive: true,
    ),
  ),
  (
    name: 'Nothing reported',
    snapshot: VehicleSnapshot(
      basicState: BasicState(),
      advancedState: AdvancedState(),
    ),
  ),
];
