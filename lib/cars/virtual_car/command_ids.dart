import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';

/// The device's ids for the virtual car's commands: their field numbers in the
/// `BasicCommand` / `AdvancedCommand` oneofs, read from the generated messages.
final kDoorLockCommand = (
  set: CommandSet.basic,
  id: commandId(BasicCommand(), 'doorLock'),
);
final kToggleCustomState1Command = (
  set: CommandSet.advanced,
  id: commandId(AdvancedCommand(), 'toggleCustomState1'),
);
