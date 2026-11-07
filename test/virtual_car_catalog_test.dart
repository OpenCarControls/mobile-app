import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/cars/virtual_car/virtual_car_definition.dart';
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

const _car = VirtualCarDefinition();

VehicleSnapshot _snapshot({bool advancedLive = true}) => VehicleSnapshot(
  basicState: BasicState(odometer: 1234, isDriving: true, areDoorsLocked: true),
  advancedState: AdvancedState(
    speed: 42,
    gear: AdvancedState_Gear.GEAR_DRIVE,
    customState1: true,
  ),
  isAdvancedStateLive: advancedLive,
);

TileValue? _value(String id, VehicleSnapshot s) =>
    (_car.tileById(id)! as StateTileDefinition).value(s, kMetricUnits);

void main() {
  test('state tiles read the state', () {
    final s = _snapshot();
    expect(_value('odometer', s).toString(), '1234 km');
    expect(_value('speed', s).toString(), '42 km/h');
    expect(_value('gear', s).toString(), 'D');
    expect(_value('driving', s).toString(), 'Yes');
  });

  test('advanced tiles show nothing until the advanced state is live', () {
    final s = _snapshot(advancedLive: false);
    expect(_value('speed', s), isNull);
    expect(_value('gear', s), isNull);
    final custom = _car.tileById('custom_state_1')! as CommandTileDefinition;
    expect(custom.state(s), kUnknownTileState);
  });

  test('the doors tile unlocks locked doors', () {
    final doors = _car.tileById('doors')! as CommandTileDefinition;
    final s = _snapshot();
    expect(doors.state(s).caption, 'Locked');
    final command = doors.command.build(s) as BasicCommand;
    expect(command.doorLock.lock, isFalse);
  });

  test('the header says driving, with the live speed', () {
    expect(_car.statusLine(_snapshot()), 'Driving');
    expect(_car.drivingSpeedKmh(_snapshot()), 42);
    expect(_car.drivingSpeedKmh(_snapshot(advancedLive: false)), isNull);
  });
}
