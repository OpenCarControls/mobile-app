import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/cars/egmp/command_ids.dart';
import 'package:open_car_app/cars/egmp/state_access.dart';
import 'package:open_car_app/cars/egmp/units.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/widgets/tiles/tile_icon.dart';

typedef _Seat = BasicState_SeatClimate;

int? _seatLevel(_Seat seat) => switch (seat) {
  _Seat.SEAT_CLIMATE_OFF => 0,
  _Seat.SEAT_CLIMATE_HEAT_LEVEL_1 => 1,
  _Seat.SEAT_CLIMATE_HEAT_LEVEL_2 => 2,
  _Seat.SEAT_CLIMATE_HEAT_LEVEL_3 => 3,
  _ => null,
};

_Seat _seatOf(int level) => switch (level) {
  1 => _Seat.SEAT_CLIMATE_HEAT_LEVEL_1,
  2 => _Seat.SEAT_CLIMATE_HEAT_LEVEL_2,
  3 => _Seat.SEAT_CLIMATE_HEAT_LEVEL_3,
  _ => _Seat.SEAT_CLIMATE_OFF,
};

/// The next level as the car's seat button steps them: off, 3, 2, 1, off.
int _nextSeatLevel(int? level) => switch (level) {
  3 => 2,
  2 => 1,
  1 => 0,
  _ => 3,
};

/// A climate command that keeps climate as it is and changes one setting.
BasicCommand _climateCommand(
  VehicleSnapshot s,
  void Function(ClimateControlCommand command) change,
) {
  final command = ClimateControlCommand(climateOn: egmpBasic(s).isClimateOn);
  change(command);
  return BasicCommand(climateControlCommand: command);
}

final egmpClimate = ClimateDescription(
  command: kClimateControlCommand,
  isOn: (s) =>
      reportedFlag(egmpBasic(s).hasIsClimateOn(), egmpBasic(s).isClimateOn),
  insideCelsius: (s) => egmpBasic(s).hasIndoorTemperature()
      ? egmpBasic(s).indoorTemperature
      : null,
  outsideCelsius: (s) => egmpBasic(s).hasOutdoorTemperature()
      ? egmpBasic(s).outdoorTemperature
      : null,
  targetCelsius: (s) => egmpBasic(s).hasTargetClimateTemperature()
      ? egmpBasic(s).targetClimateTemperature
      : null,
  minCelsius: 17,
  maxCelsius: 27,
  stepCelsius: 0.5,
  formatTarget: formatEgmpClimateTarget,
  power: (s, on) =>
      BasicCommand(climateControlCommand: ClimateControlCommand(climateOn: on)),
  setTarget: (s, celsius) =>
      _climateCommand(s, (c) => c.targetTemperature = celsius),
  extras: [
    ToggleClimateExtra(
      id: 'windshield_defrost',
      label: 'Windshield defrost',
      icon: const TileIcon.symbol(Symbols.windshield_defrost_front),
      isOn: (s) => reportedFlag(
        egmpBasic(s).hasIsWindshieldDefrostOn(),
        egmpBasic(s).isWindshieldDefrostOn,
      ),
      command: (s, on) => _climateCommand(s, (c) => c.windshieldDefrostOn = on),
    ),
    ToggleClimateExtra(
      id: 'rear_defrost',
      label: 'Rear window defrost',
      icon: const TileIcon.symbol(Symbols.windshield_defrost_rear),
      isOn: (s) => reportedFlag(
        egmpBasic(s).hasIsRearWindowDefrostOn(),
        egmpBasic(s).isRearWindowDefrostOn,
      ),
      command: (s, on) => _climateCommand(s, (c) => c.rearWindowDefrostOn = on),
    ),
    ToggleClimateExtra(
      id: 'steering_wheel_heater',
      label: 'Steering wheel heater',
      icon: const TileIcon.symbol(Symbols.steering_wheel_heat),
      isOn: (s) => reportedFlag(
        egmpBasic(s).hasIsSteeringWheelHeaterOn(),
        egmpBasic(s).isSteeringWheelHeaterOn,
      ),
      command: (s, on) =>
          _climateCommand(s, (c) => c.steeringWheelHeaterOn = on),
    ),
    // The driver sits on the left: left-hand drive is assumed.
    LeveledClimateExtra(
      id: 'driver_seat',
      label: 'Driver seat heating',
      icon: const TileIcon.symbol(Symbols.seat_heat_left),
      side: ClimateSide.left,
      levels: 3,
      level: (s) => _seatLevel(egmpBasic(s).driverSeatClimate),
      next: _nextSeatLevel,
      command: (s, level) =>
          _climateCommand(s, (c) => c.driverSeatClimate = _seatOf(level)),
    ),
    LeveledClimateExtra(
      id: 'passenger_seat',
      label: 'Passenger seat heating',
      icon: const TileIcon.symbol(Symbols.seat_heat_right),
      side: ClimateSide.right,
      levels: 3,
      level: (s) => _seatLevel(egmpBasic(s).passengerSeatClimate),
      next: _nextSeatLevel,
      command: (s, level) =>
          _climateCommand(s, (c) => c.passengerSeatClimate = _seatOf(level)),
    ),
  ],
);

/// Not in the catalog until the firmware implements the climate command:
/// `egmpTemperatureChartTile` shows the temperatures meanwhile.
final egmpClimateTile = ClimateTileDefinition(
  id: 'climate',
  label: 'Climate',
  tier: TileTier.basic,
  climate: egmpClimate,
);
