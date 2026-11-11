import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/cars/egmp/catalog.dart';
import 'package:open_car_app/cars/egmp/egmp_definition.dart';
import 'package:open_car_app/cars/egmp/tiles/battery_preconditioning.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

const _car = EgmpDefinition();

typedef _Port = BasicState_ChargePortState;
typedef _Seat = BasicState_SeatClimate;
typedef _Window = BasicState_WindowPosition;

VehicleSnapshot _snapshot(BasicState basic, {AdvancedState? advanced}) =>
    VehicleSnapshot(
      basicState: basic,
      advancedState: advanced ?? AdvancedState(),
      isAdvancedStateLive: advanced != null,
    );

TileValue? _value(String id, VehicleSnapshot s) =>
    (_car.tileById(id)! as StateTileDefinition).value(s, _car.units(s));

CommandTileDefinition _command(String id) => [
  ..._car.tiles.whereType<CommandTileDefinition>(),
  ...egmpCommandTiles,
].singleWhere((tile) => tile.id == id);

void main() {
  group('status line', () {
    test('AC charging: power and time to the AC limit', () {
      final s = _snapshot(
        BasicState(
          chargePortState: _Port.CHARGE_PORT_STATE_AC_CHARGING,
          powerFlowWatt: 7200,
          timeRemainingMinutes: 65,
          acChargeLimitPercent: 80,
          dcChargeLimitPercent: 90,
        ),
      );
      expect(_car.statusLine(s), 'Charging · 7.2 kW · 1 h 5 min to 80%');
    });

    test('DC charging adds the time to 80%', () {
      final s = _snapshot(
        BasicState(
          chargePortState: _Port.CHARGE_PORT_STATE_DC_CHARGING,
          powerFlowWatt: 150000,
          timeRemainingMinutes: 30,
          timeTo80PercentMinutes: 18,
          dcChargeLimitPercent: 90,
        ),
      );
      expect(
        _car.statusLine(s),
        'Charging · 150.0 kW · 30 min to 90% · 18 min to 80%',
      );
    });

    test('driving hides charging', () {
      final s = _snapshot(
        BasicState(
          isDriving: true,
          speed: 88,
          chargePortState: _Port.CHARGE_PORT_STATE_AC_CHARGING,
        ),
      );
      expect(_car.statusLine(s), 'Driving');
      expect(_car.drivingSpeedKmh(s), 88);
    });

    test('says nothing when parked', () {
      expect(_car.statusLine(_snapshot(BasicState())), isNull);
      expect(_car.drivingSpeedKmh(_snapshot(BasicState(speed: 0))), isNull);
    });

    test('V2L and live preconditioning', () {
      final s = _snapshot(
        BasicState(
          chargePortState: _Port.CHARGE_PORT_STATE_V2L_ACTIVE,
          powerFlowWatt: -1800,
        ),
        advanced: AdvancedState(
          preconditioningState:
              AdvancedState_PreconditioningState.PRECONDITIONING_STATE_HEATING,
        ),
      );
      expect(
        _car.statusLine(s),
        'Exporting power · 1.8 kW · Battery preconditioning: heating',
      );
    });
  });

  group('climate', () {
    final climate = _car.climate!;

    test('seats step off, 3, 2, 1, off', () {
      final seat = climate.extras.whereType<LeveledClimateExtra>().first;
      expect(seat.side, ClimateSide.left);
      final steps = <int?>[0];
      for (var i = 0; i < 4; i++) {
        steps.add(seat.next(steps.last));
      }
      expect(steps, [0, 3, 2, 1, 0]);
      expect(seat.next(null), 3);

      final s = _snapshot(
        BasicState(
          isClimateOn: true,
          driverSeatClimate: _Seat.SEAT_CLIMATE_OFF,
        ),
      );
      expect(seat.level(s), 0);
      final command =
          (seat.command(s, 2) as BasicCommand).climateControlCommand;
      expect(command.climateOn, isTrue);
      expect(command.driverSeatClimate, _Seat.SEAT_CLIMATE_HEAT_LEVEL_2);
    });

    test('the target keeps climate on and steps 0.5 °C', () {
      final s = _snapshot(
        BasicState(isClimateOn: true, targetClimateTemperature: 21),
      );
      expect(climate.stepCelsius, 0.5);
      final command =
          (climate.setTarget(s, 21.5) as BasicCommand).climateControlCommand;
      expect(command.climateOn, isTrue);
      expect(command.targetTemperature, 21.5);
    });

    test('unknown values stay unknown', () {
      final s = _snapshot(BasicState());
      expect(climate.isOn(s), isNull);
      expect(climate.insideCelsius(s), isNull);
      expect(climate.targetCelsius(s), isNull);
    });
  });

  group('tiles', () {
    test('only the commands the firmware implements are offered', () {
      expect(
        [
          for (final tile in _car.tiles)
            if (tile.command != null || tile is ClimateTileDefinition) tile.id,
        ],
        ['battery_preconditioning'],
      );
    });

    group('battery preconditioning', () {
      final tile = _command('battery_preconditioning');
      VehicleSnapshot advanced(
        AdvancedState_PreconditioningState state, {
        bool manual = false,
        AdvancedState_PowerState power =
            AdvancedState_PowerState.POWER_STATE_READY,
      }) => _snapshot(
        BasicState(),
        advanced: AdvancedState(
          preconditioningState: state,
          isManualPreconditioningRequested: manual,
          powerState: power,
        ),
      );
      const off = AdvancedState_PreconditioningState.PRECONDITIONING_STATE_OFF;
      const preparing =
          AdvancedState_PreconditioningState.PRECONDITIONING_STATE_PREPARING;
      const heating =
          AdvancedState_PreconditioningState.PRECONDITIONING_STATE_HEATING;

      test('shows the state, whoever started it', () {
        expect(tile.state(advanced(off)).caption, 'Disabled');
        expect(tile.state(advanced(off, manual: true)).caption, 'Starting');
        expect(tile.state(advanced(preparing)).caption, 'Starting');
        expect(tile.state(advanced(heating)).caption, 'Enabled');
        expect(tile.state(advanced(heating)).on, isTrue);
        expect(
          tile.state(_snapshot(BasicState())),
          kUnknownTileState,
          reason: 'advanced state not live',
        );
      });

      test('a tap starts it, or stops our own session', () {
        bool enable(VehicleSnapshot s) =>
            (tile.command.build(s) as AdvancedCommand)
                .batteryPreconditioningCommand
                .enable;
        expect(enable(advanced(off)), isTrue);
        expect(enable(advanced(heating, manual: true)), isFalse);
        expect(
          tile.command.activityName(advanced(heating, manual: true)),
          'Stop battery preconditioning',
        );
      });

      test("says why it can't be used", () {
        final reason = tile.command.unavailableReason!;
        expect(
          reason(advanced(heating)),
          'The car is preconditioning the battery on its own.',
        );
        expect(reason(advanced(heating, manual: true)), isNull);
        expect(
          reason(advanced(off, power: AdvancedState_PowerState.POWER_STATE_ON)),
          'The car needs to be in Ready.',
        );
        expect(reason(advanced(off)), isNull);
      });
    });

    test('temperature shows inside and outside side by side', () {
      final temperature = _car.tileById('temperature')! as CustomTileDefinition;
      expect(temperature.sizes, [const TileSpan(2, 1)]);
      String describe(BasicState basic) {
        final s = _snapshot(basic);
        return temperature.describe((
          snapshot: s,
          units: _car.units(s),
          span: temperature.sizes.first,
        ));
      }

      expect(
        describe(BasicState(indoorTemperature: 19.5, outdoorTemperature: 12)),
        'inside 19.5 °C, outside 12.0 °C',
      );
      expect(
        describe(
          BasicState(
            indoorTemperature: 20,
            temperatureUnit:
                BasicState_TemperatureUnit.TEMPERATURE_UNIT_FAHRENHEIT,
          ),
        ),
        'inside 68 °F, outside unknown',
      );
    });

    test('windows close when any is open, vent otherwise', () {
      final windows = _command('windows');
      final closed = _snapshot(
        BasicState(
          driverWindowPosition: _Window.WINDOW_POSITION_CLOSED,
          passengerWindowPosition: _Window.WINDOW_POSITION_CLOSED,
        ),
      );
      final open = _snapshot(
        BasicState(
          driverWindowPosition: _Window.WINDOW_POSITION_CLOSED,
          rearLeftWindowPosition: _Window.WINDOW_POSITION_PARTLY_OPEN,
        ),
      );
      expect(windows.state(closed).caption, 'Closed');
      expect(windows.state(open).caption, 'Open');
      expect(windows.state(_snapshot(BasicState())), kUnknownTileState);
      expect(
        (windows.command.build(closed) as BasicCommand).windowCommand.action,
        WindowCommand_WindowAction.WINDOW_ACTION_VENT,
      );
      expect(
        (windows.command.build(open) as BasicCommand).windowCommand.action,
        WindowCommand_WindowAction.WINDOW_ACTION_CLOSE,
      );
      expect(
        _value('window_status', open).toString(),
        '1 open Rear left partly open',
      );
    });

    test('charge port captions', () {
      String caption(_Port port) => _command(
        'charge_port',
      ).state(_snapshot(BasicState(chargePortState: port))).caption;
      expect(caption(_Port.CHARGE_PORT_STATE_CLOSED), 'Closed');
      expect(caption(_Port.CHARGE_PORT_STATE_DC_CHARGING), 'Charging');
      expect(caption(_Port.CHARGE_PORT_STATE_CONNECTED), 'Plugged in');
      expect(caption(_Port.CHARGE_PORT_STATE_UNSPECIFIED), 'Unknown');
    });

    test('door status lists the open doors', () {
      final s = _snapshot(
        BasicState(isDriverDoorOpen: true, isPassengerDoorOpen: false),
      );
      expect(_value('door_status', s).toString(), '1 open Driver');
      expect(_value('door_status', _snapshot(BasicState())), isNull);
    });

    test('distances and temperatures follow the car units', () {
      final s = _snapshot(
        BasicState(
          odometer: 22916,
          distanceUnit: BasicState_DistanceUnit.DISTANCE_UNIT_MILES,
          temperatureUnit:
              BasicState_TemperatureUnit.TEMPERATURE_UNIT_FAHRENHEIT,
        ),
        advanced: AdvancedState(
          batteryMinimumTemperature: 24,
          batteryMaximumTemperature: 27,
        ),
      );
      expect(_value('odometer', s).toString(), '14239 mi');
      expect(
        egmpPackTemperature(s, _car.units(s).temperature).toString(),
        '75–81 °F',
      );
    });

    test('advanced tiles wait for live advanced state', () {
      final advanced = AdvancedState(
        batteryVoltage: 697,
        gear: AdvancedState_Gear.GEAR_PARK,
        powerState: AdvancedState_PowerState.POWER_STATE_OFF,
      );
      final live = _snapshot(BasicState(), advanced: advanced);
      final cached = VehicleSnapshot(
        basicState: BasicState(),
        advancedState: advanced,
      );
      for (final (id, shown) in [
        ('pack_voltage', '697 V'),
        ('gear', 'P'),
        ('power_state', 'Off'),
      ]) {
        expect(_value(id, live).toString(), shown, reason: id);
        expect(_value(id, cached), isNull, reason: id);
      }
    });
  });
}
