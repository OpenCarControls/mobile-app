import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';

/// The device's ids for the E-GMP commands: their field numbers in the
/// `BasicCommand` / `AdvancedCommand` oneofs, read from the generated messages.
final kDoorLockCommand = (
  set: CommandSet.basic,
  id: commandId(BasicCommand(), 'doorLockCommand'),
);
final kChargePortCommand = (
  set: CommandSet.basic,
  id: commandId(BasicCommand(), 'chargePortCommand'),
);
final kFlashLightsCommand = (
  set: CommandSet.basic,
  id: commandId(BasicCommand(), 'flashLightsCommand'),
);
final kClimateControlCommand = (
  set: CommandSet.basic,
  id: commandId(BasicCommand(), 'climateControlCommand'),
);
final kWindowCommand = (
  set: CommandSet.basic,
  id: commandId(BasicCommand(), 'windowCommand'),
);
final kBatteryPreconditioningCommand = (
  set: CommandSet.advanced,
  id: commandId(AdvancedCommand(), 'batteryPreconditioningCommand'),
);
