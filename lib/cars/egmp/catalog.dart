import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/cars/egmp/command_ids.dart';
import 'package:open_car_app/cars/egmp/units.dart';
import 'package:open_car_app/cars/egmp/widgets/chart_tiles.dart';
import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/widgets/tiles/car_body_icons.dart';
import 'package:open_car_app/widgets/tiles/history_chart.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';
import 'package:open_car_app/widgets/tiles/tile_icon.dart';

BasicState _basic(VehicleSnapshot s) => s.basicState as BasicState;

/// The advanced state, only while it is live over this transport.
AdvancedState? _advanced(VehicleSnapshot s) =>
    s.isAdvancedStateLive ? s.advancedState as AdvancedState : null;

/// The car's display units.
VehicleUnits egmpUnits(VehicleSnapshot s) => (
  distance: _basic(s).displayDistanceUnit,
  temperature: _basic(s).displayTemperatureUnit,
);

// ── Energy ──────────────────────────────────────────────────────────────────

typedef _Port = BasicState_ChargePortState;

const _charging = {
  _Port.CHARGE_PORT_STATE_AC_CHARGING,
  _Port.CHARGE_PORT_STATE_DC_CHARGING,
};

EnergyStatus _energyStatus(VehicleSnapshot s) {
  final b = _basic(s);
  final power = b.hasPowerFlowWatt() && b.powerFlowWatt != 0
      ? b.powerFlowWatt.abs()
      : null;
  final dc = b.chargePortState == _Port.CHARGE_PORT_STATE_DC_CHARGING;
  // Like the cluster: the time to the limit that applies, and on DC to 80%.
  final limit = dc
      ? (b.hasDcChargeLimitPercent() ? b.dcChargeLimitPercent : null)
      : (b.hasAcChargeLimitPercent() ? b.acChargeLimitPercent : null);
  if (_charging.contains(b.chargePortState)) {
    return EnergyStatus(
      flow: EnergyFlow.charging,
      powerWatts: power,
      limitPercent: limit,
      timeToLimitMinutes: b.hasTimeRemainingMinutes()
          ? b.timeRemainingMinutes
          : null,
      timeTo80PercentMinutes: dc && b.hasTimeTo80PercentMinutes()
          ? b.timeTo80PercentMinutes
          : null,
    );
  }
  if (b.chargePortState == _Port.CHARGE_PORT_STATE_V2L_ACTIVE) {
    return EnergyStatus(flow: EnergyFlow.exporting, powerWatts: power);
  }
  return EnergyStatus(limitPercent: limit);
}

final egmpBattery = EnergyDescription(
  kind: EnergyKind.battery,
  levelPercent: (s) => _basic(s).hasBatterySoc() ? _basic(s).batterySoc : null,
  rangeKm: (s) =>
      _basic(s).hasBatteryRangeKm() ? _basic(s).batteryRangeKm : null,
  status: _energyStatus,
);

// ── Header ──────────────────────────────────────────────────────────────────

int? egmpDrivingSpeedKmh(VehicleSnapshot s) =>
    _basic(s).isDriving && _basic(s).hasSpeed() ? _basic(s).speed : null;

String? egmpStatusLine(VehicleSnapshot s) {
  // While driving the speed is in the level row, and charging text is hidden.
  if (_basic(s).isDriving) return 'Driving';
  final status = _energyStatus(s);
  final power = status.powerWatts;
  final energy = switch (status.flow) {
    EnergyFlow.charging => [
      'Charging',
      if (power != null) formatKilowatts(power),
      ?status.timeText,
    ].join(' · '),
    EnergyFlow.exporting => [
      'Exporting power',
      if (power != null) formatKilowatts(power),
    ].join(' · '),
    EnergyFlow.idle => null,
  };
  final preconditioning = switch (_advanced(s)?.preconditioningState) {
    AdvancedState_PreconditioningState.PRECONDITIONING_STATE_PREPARING =>
      'Battery preconditioning: preparing',
    AdvancedState_PreconditioningState.PRECONDITIONING_STATE_HEATING =>
      'Battery preconditioning: heating',
    _ => null,
  };
  final parts = [?energy, ?preconditioning];
  return parts.isEmpty ? null : parts.join(' · ');
}

// ── Climate ─────────────────────────────────────────────────────────────────

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
  final command = ClimateControlCommand(climateOn: _basic(s).isClimateOn);
  change(command);
  return BasicCommand(climateControlCommand: command);
}

/// A reported flag, or null when the car hasn't reported it.
bool? _flag(bool has, bool value) => has ? value : null;

final egmpClimate = ClimateDescription(
  command: kClimateControlCommand,
  isOn: (s) => _flag(_basic(s).hasIsClimateOn(), _basic(s).isClimateOn),
  insideCelsius: (s) =>
      _basic(s).hasIndoorTemperature() ? _basic(s).indoorTemperature : null,
  outsideCelsius: (s) =>
      _basic(s).hasOutdoorTemperature() ? _basic(s).outdoorTemperature : null,
  targetCelsius: (s) => _basic(s).hasTargetClimateTemperature()
      ? _basic(s).targetClimateTemperature
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
      isOn: (s) => _flag(
        _basic(s).hasIsWindshieldDefrostOn(),
        _basic(s).isWindshieldDefrostOn,
      ),
      command: (s, on) => _climateCommand(s, (c) => c.windshieldDefrostOn = on),
    ),
    ToggleClimateExtra(
      id: 'rear_defrost',
      label: 'Rear window defrost',
      icon: const TileIcon.symbol(Symbols.windshield_defrost_rear),
      isOn: (s) => _flag(
        _basic(s).hasIsRearWindowDefrostOn(),
        _basic(s).isRearWindowDefrostOn,
      ),
      command: (s, on) => _climateCommand(s, (c) => c.rearWindowDefrostOn = on),
    ),
    ToggleClimateExtra(
      id: 'steering_wheel_heater',
      label: 'Steering wheel heater',
      icon: const TileIcon.symbol(Symbols.steering_wheel_heat),
      isOn: (s) => _flag(
        _basic(s).hasIsSteeringWheelHeaterOn(),
        _basic(s).isSteeringWheelHeaterOn,
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
      level: (s) => _seatLevel(_basic(s).driverSeatClimate),
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
      level: (s) => _seatLevel(_basic(s).passengerSeatClimate),
      next: _nextSeatLevel,
      command: (s, level) =>
          _climateCommand(s, (c) => c.passengerSeatClimate = _seatOf(level)),
    ),
  ],
);

// ── Body ────────────────────────────────────────────────────────────────────

typedef _Window = BasicState_WindowPosition;

/// The window positions by name, in the car's order.
List<(String, _Window)> _windows(BasicState b) => [
  ('Driver', b.driverWindowPosition),
  ('Passenger', b.passengerWindowPosition),
  ('Rear left', b.rearLeftWindowPosition),
  ('Rear right', b.rearRightWindowPosition),
];

bool _isOpen(_Window position) =>
    position != _Window.WINDOW_POSITION_CLOSED &&
    position != _Window.WINDOW_POSITION_UNSPECIFIED;

String _windowWord(_Window position) => switch (position) {
  _Window.WINDOW_POSITION_SLIGHTLY_OPEN => 'slightly open',
  _Window.WINDOW_POSITION_PARTLY_OPEN => 'partly open',
  _Window.WINDOW_POSITION_FULLY_OPEN => 'fully open',
  _ => 'closed',
};

/// Whether any window is open; null until the car reports them.
bool? _anyWindowOpen(BasicState b) {
  final positions = [for (final (_, p) in _windows(b)) p];
  if (positions.every((p) => p == _Window.WINDOW_POSITION_UNSPECIFIED)) {
    return null;
  }
  return positions.any(_isOpen);
}

/// The open doors by name, or null until the car reports them.
List<String>? _openDoors(BasicState b) {
  final doors = [
    ('Driver', b.hasIsDriverDoorOpen(), b.isDriverDoorOpen),
    ('Passenger', b.hasIsPassengerDoorOpen(), b.isPassengerDoorOpen),
    ('Rear left', b.hasIsRearLeftDoorOpen(), b.isRearLeftDoorOpen),
    ('Rear right', b.hasIsRearRightDoorOpen(), b.isRearRightDoorOpen),
  ];
  if (!doors.any((d) => d.$2)) return null;
  return [
    for (final (name, _, open) in doors)
      if (open) name,
  ];
}

TileState _openClosed(bool? open) => switch (open) {
  null => kUnknownTileState,
  true => const TileState(on: true, caption: 'Open'),
  false => const TileState(on: false, caption: 'Closed'),
};

TileState _chargePortState(VehicleSnapshot s) {
  final caption = switch (_basic(s).chargePortState) {
    _Port.CHARGE_PORT_STATE_UNSPECIFIED => null,
    _Port.CHARGE_PORT_STATE_CLOSED => 'Closed',
    _Port.CHARGE_PORT_STATE_OPEN => 'Open',
    _Port.CHARGE_PORT_STATE_AC_CHARGING ||
    _Port.CHARGE_PORT_STATE_DC_CHARGING => 'Charging',
    _Port.CHARGE_PORT_STATE_V2L_ACTIVE => 'V2L on',
    _Port.CHARGE_PORT_STATE_V2L_CONNECTED => 'V2L',
    _Port.CHARGE_PORT_STATE_AC_ERROR ||
    _Port.CHARGE_PORT_STATE_DC_ERROR ||
    _Port.CHARGE_PORT_STATE_V2L_ERROR => 'Error',
    _ => 'Plugged in',
  };
  if (caption == null) return kUnknownTileState;
  return TileState(on: caption != 'Closed', caption: caption);
}

// ── Advanced values ─────────────────────────────────────────────────────────

int? _powerWatts(VehicleSnapshot s) => switch (_advanced(s)) {
  final a? when a.hasInstantaneousPowerWatt() => a.instantaneousPowerWatt,
  _ => null,
};

final _powerSeries = HistorySeries(
  id: 'battery_power',
  sample: (s) => _powerWatts(s)?.toDouble(),
);

final _packMinSeries = HistorySeries(
  id: 'pack_temperature_min',
  sample: (s) => switch (_advanced(s)) {
    final a? when a.hasBatteryMinimumTemperature() =>
      a.batteryMinimumTemperature,
    _ => null,
  },
);

final _packMaxSeries = HistorySeries(
  id: 'pack_temperature_max',
  sample: (s) => switch (_advanced(s)) {
    final a? when a.hasBatteryMaximumTemperature() =>
      a.batteryMaximumTemperature,
    _ => null,
  },
);

final _speedSeries = HistorySeries(
  id: 'speed',
  sample: (s) => _basic(s).hasSpeed() ? _basic(s).speed.toDouble() : null,
);

TileValue? _powerValue(VehicleSnapshot s) {
  final watts = _powerWatts(s);
  if (watts == null) return null;
  return TileValue.formatted(
    formatKilowatts(watts.abs()),
    note: watts > 0
        ? 'charging'
        : watts < 0
        ? 'discharging'
        : 'idle',
  );
}

/// The pack's temperature range in the car's unit ("24–27 °C").
TileValue? _packTemperature(VehicleSnapshot s, TemperatureUnit unit) {
  final low = _packMinSeries.sample(s);
  final high = _packMaxSeries.sample(s);
  if (low == null || high == null) return null;
  String degrees(double c) => switch (unit) {
    TemperatureUnit.celsius => c.round().toString(),
    TemperatureUnit.fahrenheit => celsiusToFahrenheit(c).round().toString(),
  };
  final range = degrees(low) == degrees(high)
      ? degrees(low)
      : '${degrees(low)}–${degrees(high)}';
  return TileValue(range, unit: unit == TemperatureUnit.celsius ? '°C' : '°F');
}

String _powerStateWord(AdvancedState_PowerState state) => switch (state) {
  AdvancedState_PowerState.POWER_STATE_OFF => 'Off',
  AdvancedState_PowerState.POWER_STATE_ACCESSORY => 'Acc',
  AdvancedState_PowerState.POWER_STATE_ON => 'On',
  AdvancedState_PowerState.POWER_STATE_READY => 'Ready',
  _ => '?',
};

String _gearLetter(AdvancedState_Gear gear) => switch (gear) {
  AdvancedState_Gear.GEAR_PARK => 'P',
  AdvancedState_Gear.GEAR_REVERSE => 'R',
  AdvancedState_Gear.GEAR_NEUTRAL => 'N',
  AdvancedState_Gear.GEAR_DRIVE => 'D',
  _ => '?',
};

// ── Catalog ─────────────────────────────────────────────────────────────────

final egmpTiles = <TileDefinition>[
  // Buttons.
  CommandTileDefinition(
    id: 'doors',
    label: 'Doors',
    accessibleLabel: 'Door lock',
    tier: TileTier.basic,
    icon: const TileIcon.symbol(Symbols.lock_open, onSymbol: Symbols.lock),
    command: TileCommand(
      key: kDoorLockCommand,
      build: (s) => BasicCommand(
        doorLockCommand: DoorLockCommand(lock: !_basic(s).areDoorsLocked),
      ),
      activityName: (s) =>
          _basic(s).areDoorsLocked ? 'Unlock doors' : 'Lock doors',
    ),
    state: (s) => switch (_flag(
      _basic(s).hasAreDoorsLocked(),
      _basic(s).areDoorsLocked,
    )) {
      null => kUnknownTileState,
      true => const TileState(on: true, caption: 'Locked'),
      false => const TileState(on: false, caption: 'Unlocked'),
    },
  ),
  CommandTileDefinition(
    id: 'charge_port',
    label: 'Port',
    accessibleLabel: 'Charge port',
    tier: TileTier.basic,
    icon: const TileIcon.symbol(Symbols.ev_charger),
    command: TileCommand(
      key: kChargePortCommand,
      build: (s) => BasicCommand(
        chargePortCommand: ChargePortCommand(
          open: _basic(s).chargePortState != _Port.CHARGE_PORT_STATE_OPEN,
        ),
      ),
      activityName: (s) =>
          _basic(s).chargePortState != _Port.CHARGE_PORT_STATE_OPEN
          ? 'Open charge port'
          : 'Close charge port',
    ),
    state: _chargePortState,
  ),
  CommandTileDefinition(
    id: 'lights',
    label: 'Lights',
    accessibleLabel: 'Flash lights',
    tier: TileTier.basic,
    icon: const TileIcon.symbol(Symbols.lightbulb),
    command: TileCommand(
      key: kFlashLightsCommand,
      build: (_) => BasicCommand(flashLightsCommand: FlashLightsCommand()),
      activityName: (_) => 'Flash lights',
    ),
    // Flashing is momentary: there is no on state to show.
    state: (_) => const TileState(on: false, caption: 'Flash'),
  ),
  CommandTileDefinition(
    id: 'windows',
    label: 'Windows',
    tier: TileTier.basic,
    icon: CarBodyIcons.window,
    // Closes open windows, and vents closed ones.
    command: TileCommand(
      key: kWindowCommand,
      build: (s) => BasicCommand(
        windowCommand: WindowCommand(
          action: _anyWindowOpen(_basic(s)) ?? false
              ? WindowCommand_WindowAction.WINDOW_ACTION_CLOSE
              : WindowCommand_WindowAction.WINDOW_ACTION_VENT,
        ),
      ),
      activityName: (s) =>
          _anyWindowOpen(_basic(s)) ?? false ? 'Close windows' : 'Vent windows',
    ),
    state: (s) => _openClosed(_anyWindowOpen(_basic(s))),
  ),

  // Energy and climate.
  EnergyTileDefinition(
    id: 'battery',
    label: 'Battery',
    tier: TileTier.basic,
    energy: egmpBattery,
  ),
  ClimateTileDefinition(
    id: 'climate',
    label: 'Climate',
    tier: TileTier.basic,
    climate: egmpClimate,
  ),

  // Body state.
  StateTileDefinition(
    id: 'door_status',
    label: 'Doors',
    accessibleLabel: 'Open doors',
    tier: TileTier.basic,
    icon: const TileIcon.symbol(Symbols.door_open),
    value: (s, _) => switch (_openDoors(_basic(s))) {
      null => null,
      [] => const TileValue('Closed'),
      final open => TileValue('${open.length} open', note: open.join(', ')),
    },
  ),
  StateTileDefinition(
    id: 'window_status',
    label: 'Windows',
    accessibleLabel: 'Window positions',
    tier: TileTier.basic,
    icon: CarBodyIcons.window,
    value: (s, _) {
      final b = _basic(s);
      if (_anyWindowOpen(b) == null) return null;
      final open = [
        for (final (name, position) in _windows(b))
          if (_isOpen(position)) '$name ${_windowWord(position)}',
      ];
      return open.isEmpty
          ? const TileValue('Closed')
          : TileValue('${open.length} open', note: open.join(', '));
    },
  ),
  StateTileDefinition(
    id: 'frunk',
    label: 'Frunk',
    tier: TileTier.basic,
    icon: CarBodyIcons.frunk,
    sizes: const [TileSpan(1, 1)],
    value: (s, _) => _basic(s).hasIsFrunkOpen()
        ? TileValue(_basic(s).isFrunkOpen ? 'Open' : 'Closed')
        : null,
  ),
  StateTileDefinition(
    id: 'trunk',
    label: 'Trunk',
    tier: TileTier.basic,
    icon: CarBodyIcons.trunk,
    sizes: const [TileSpan(1, 1)],
    value: (s, _) => _basic(s).hasIsTrunkOpen()
        ? TileValue(_basic(s).isTrunkOpen ? 'Open' : 'Closed')
        : null,
  ),

  // Driving.
  StateTileDefinition(
    id: 'odometer',
    label: 'Odometer',
    tier: TileTier.basic,
    sizes: const [TileSpan(1, 1), TileSpan(2, 1)],
    value: (s, units) => _basic(s).hasOdometer()
        ? TileValue.formatted(
            formatOdometer(_basic(s).odometer, units.distance),
          )
        : null,
  ),
  StateTileDefinition(
    id: 'speed',
    label: 'Speed',
    tier: TileTier.basic,
    history: _speedSeries,
    value: (s, units) => _basic(s).hasSpeed()
        ? TileValue.formatted(formatSpeed(_basic(s).speed, units.distance))
        : null,
  ),

  // Advanced values.
  ChartTileDefinition(
    id: 'battery_power',
    label: 'Power',
    accessibleLabel: 'Battery power',
    tier: TileTier.advanced,
    sizes: const [TileSpan(2, 1), TileSpan(2, 2), TileSpan(4, 2)],
    series: [_powerSeries],
    describe: (data) => _powerValue(data.snapshot)?.toString() ?? 'unknown',
    builder: (context, data) => EgmpChartTile(
      label: 'Power',
      value: _powerValue(data.snapshot),
      span: data.span,
      chart: HistoryChart(
        lines: [samplesIn(data, _powerSeries)],
        fromZero: true,
      ),
    ),
  ),
  ChartTileDefinition(
    id: 'pack_temperature',
    label: 'Pack temp',
    accessibleLabel: 'Battery temperature',
    tier: TileTier.advanced,
    sizes: const [TileSpan(2, 1), TileSpan(2, 2)],
    series: [_packMinSeries, _packMaxSeries],
    describe: (data) =>
        _packTemperature(data.snapshot, data.units.temperature)?.toString() ??
        'unknown',
    builder: (context, data) => EgmpChartTile(
      label: 'Pack temp',
      value: _packTemperature(data.snapshot, data.units.temperature),
      span: data.span,
      chart: HistoryChart(
        lines: [
          samplesIn(data, _packMinSeries),
          samplesIn(data, _packMaxSeries),
        ],
      ),
    ),
  ),
  StateTileDefinition(
    id: 'pack_voltage',
    label: 'Pack voltage',
    tier: TileTier.advanced,
    sizes: const [TileSpan(1, 1), TileSpan(2, 1)],
    value: (s, _) => switch (_advanced(s)) {
      final a? when a.hasBatteryVoltage() => TileValue(
        '${a.batteryVoltage}',
        unit: 'V',
      ),
      _ => null,
    },
  ),
  StateTileDefinition(
    id: 'preconditioning',
    label: 'Preheat',
    accessibleLabel: 'Battery preconditioning',
    tier: TileTier.advanced,
    icon: const TileIcon.symbol(Symbols.mode_heat),
    sizes: const [TileSpan(1, 1), TileSpan(2, 1)],
    value: (s, _) => switch (_advanced(s)?.preconditioningState) {
      AdvancedState_PreconditioningState.PRECONDITIONING_STATE_OFF =>
        const TileValue('Off'),
      AdvancedState_PreconditioningState.PRECONDITIONING_STATE_PREPARING =>
        const TileValue('Preparing'),
      AdvancedState_PreconditioningState.PRECONDITIONING_STATE_HEATING =>
        const TileValue('Heating'),
      _ => null,
    },
  ),
  StateTileDefinition(
    id: 'gear',
    label: 'Gear',
    tier: TileTier.advanced,
    sizes: const [TileSpan(1, 1)],
    value: (s, _) => switch (_advanced(s)) {
      final a? when a.hasGear() => TileValue(_gearLetter(a.gear)),
      _ => null,
    },
  ),
  StateTileDefinition(
    id: 'power_state',
    label: 'Power state',
    tier: TileTier.advanced,
    sizes: const [TileSpan(1, 1)],
    value: (s, _) => switch (_advanced(s)) {
      final a? when a.hasPowerState() => TileValue(
        _powerStateWord(a.powerState),
      ),
      _ => null,
    },
  ),

  const CarViewTileDefinition(
    id: 'car_view',
    label: 'Car view',
    tier: TileTier.basic,
  ),
];

const egmpRemoteLayout = <TileLayoutEntry>[
  (tileId: 'doors', span: TileSpan(1, 1)),
  (tileId: 'charge_port', span: TileSpan(1, 1)),
  (tileId: 'lights', span: TileSpan(1, 1)),
  (tileId: 'windows', span: TileSpan(1, 1)),
  (tileId: 'climate', span: TileSpan(4, 1)),
];

const egmpBluetoothLayout = <TileLayoutEntry>[
  (tileId: 'battery', span: TileSpan(4, 1)),
  (tileId: 'doors', span: TileSpan(1, 1)),
  (tileId: 'charge_port', span: TileSpan(1, 1)),
  (tileId: 'lights', span: TileSpan(1, 1)),
  (tileId: 'windows', span: TileSpan(1, 1)),
  (tileId: 'climate', span: TileSpan(4, 1)),
  (tileId: 'battery_power', span: TileSpan(2, 2)),
  (tileId: 'pack_voltage', span: TileSpan(1, 1)),
  (tileId: 'gear', span: TileSpan(1, 1)),
  (tileId: 'power_state', span: TileSpan(1, 1)),
  (tileId: 'preconditioning', span: TileSpan(1, 1)),
  (tileId: 'pack_temperature', span: TileSpan(2, 1)),
  (tileId: 'speed', span: TileSpan(1, 1)),
  (tileId: 'odometer', span: TileSpan(1, 1)),
];
