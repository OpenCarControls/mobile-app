import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/cars/egmp/command_ids.dart';
import 'package:open_car_app/cars/egmp/state_access.dart';
import 'package:open_car_app/cars/egmp/tiles/battery.dart';
import 'package:open_car_app/cars/egmp/tiles/pack_temperature_chart.dart';
import 'package:open_car_app/cars/egmp/tiles/power_chart.dart';
import 'package:open_car_app/cars/egmp/tiles/temperature.dart';
import 'package:open_car_app/cars/egmp/units.dart';
import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/widgets/tiles/car_body_icons.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';
import 'package:open_car_app/widgets/tiles/tile_icon.dart';

// The E-GMP tile catalog. Simple tiles are defined here; custom ones (climate,
// energy, charts) each have their own file in `tiles/`.

/// The car's display units.
VehicleUnits egmpUnits(VehicleSnapshot s) => (
  distance: egmpBasic(s).displayDistanceUnit,
  temperature: egmpBasic(s).displayTemperatureUnit,
);

// ── Header ──────────────────────────────────────────────────────────────────

int? egmpDrivingSpeedKmh(VehicleSnapshot s) =>
    egmpBasic(s).isDriving && egmpBasic(s).hasSpeed()
    ? egmpBasic(s).speed
    : null;

String? egmpStatusLine(VehicleSnapshot s) {
  // While driving the speed is in the level row, and charging text is hidden.
  if (egmpBasic(s).isDriving) return 'Driving';
  final status = egmpEnergyStatus(s);
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
  final preconditioning = switch (egmpAdvanced(s)?.preconditioningState) {
    AdvancedState_PreconditioningState.PRECONDITIONING_STATE_PREPARING =>
      'Battery preconditioning: preparing',
    AdvancedState_PreconditioningState.PRECONDITIONING_STATE_HEATING =>
      'Battery preconditioning: heating',
    _ => null,
  };
  final parts = [?energy, ?preconditioning];
  return parts.isEmpty ? null : parts.join(' · ');
}

// ── Body ────────────────────────────────────────────────────────────────────

typedef _Port = BasicState_ChargePortState;
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
  final caption = switch (egmpBasic(s).chargePortState) {
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

final _speedSeries = HistorySeries(
  id: 'speed',
  sample: (s) => egmpBasic(s).hasSpeed() ? egmpBasic(s).speed.toDouble() : null,
);

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

// ── Buttons ─────────────────────────────────────────────────────────────────

/// The command tiles, not in the catalog until the firmware implements their
/// commands. To offer one, move it into [egmpTiles] and the default layouts.
/// The climate tile waits the same way (`egmpClimateTile`).
final egmpCommandTiles = <CommandTileDefinition>[
  CommandTileDefinition(
    id: 'doors',
    label: 'Doors',
    accessibleLabel: 'Door lock',
    tier: TileTier.basic,
    icon: const TileIcon.symbol(Symbols.lock_open, onSymbol: Symbols.lock),
    command: TileCommand(
      key: kDoorLockCommand,
      build: (s) => BasicCommand(
        doorLockCommand: DoorLockCommand(lock: !egmpBasic(s).areDoorsLocked),
      ),
      activityName: (s) =>
          egmpBasic(s).areDoorsLocked ? 'Unlock doors' : 'Lock doors',
    ),
    state: (s) => switch (reportedFlag(
      egmpBasic(s).hasAreDoorsLocked(),
      egmpBasic(s).areDoorsLocked,
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
          open: egmpBasic(s).chargePortState != _Port.CHARGE_PORT_STATE_OPEN,
        ),
      ),
      activityName: (s) =>
          egmpBasic(s).chargePortState != _Port.CHARGE_PORT_STATE_OPEN
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
          action: _anyWindowOpen(egmpBasic(s)) ?? false
              ? WindowCommand_WindowAction.WINDOW_ACTION_CLOSE
              : WindowCommand_WindowAction.WINDOW_ACTION_VENT,
        ),
      ),
      activityName: (s) => _anyWindowOpen(egmpBasic(s)) ?? false
          ? 'Close windows'
          : 'Vent windows',
    ),
    state: (s) => _openClosed(_anyWindowOpen(egmpBasic(s))),
  ),
];

// ── Catalog ─────────────────────────────────────────────────────────────────

final egmpTiles = <TileDefinition>[
  // Energy and temperatures.
  egmpBatteryTile,
  egmpTemperatureTile,

  // Body state.
  StateTileDefinition(
    id: 'door_status',
    label: 'Doors',
    accessibleLabel: 'Open doors',
    tier: TileTier.basic,
    icon: const TileIcon.symbol(Symbols.door_open),
    value: (s, _) => switch (_openDoors(egmpBasic(s))) {
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
      final b = egmpBasic(s);
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
    value: (s, _) => egmpBasic(s).hasIsFrunkOpen()
        ? TileValue(egmpBasic(s).isFrunkOpen ? 'Open' : 'Closed')
        : null,
  ),
  StateTileDefinition(
    id: 'trunk',
    label: 'Trunk',
    tier: TileTier.basic,
    icon: CarBodyIcons.trunk,
    sizes: const [TileSpan(1, 1)],
    value: (s, _) => egmpBasic(s).hasIsTrunkOpen()
        ? TileValue(egmpBasic(s).isTrunkOpen ? 'Open' : 'Closed')
        : null,
  ),

  // Driving.
  StateTileDefinition(
    id: 'odometer',
    label: 'Odometer',
    tier: TileTier.basic,
    sizes: const [TileSpan(1, 1), TileSpan(2, 1)],
    value: (s, units) => egmpBasic(s).hasOdometer()
        ? TileValue.formatted(
            formatOdometer(egmpBasic(s).odometer, units.distance),
          )
        : null,
  ),
  StateTileDefinition(
    id: 'speed',
    label: 'Speed',
    tier: TileTier.basic,
    history: _speedSeries,
    value: (s, units) => egmpBasic(s).hasSpeed()
        ? TileValue.formatted(formatSpeed(egmpBasic(s).speed, units.distance))
        : null,
  ),

  // Advanced values.
  egmpPowerChartTile,
  egmpPackTemperatureChartTile,
  StateTileDefinition(
    id: 'pack_voltage',
    label: 'Pack voltage',
    tier: TileTier.advanced,
    sizes: const [TileSpan(1, 1), TileSpan(2, 1)],
    value: (s, _) => switch (egmpAdvanced(s)) {
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
    value: (s, _) => switch (egmpAdvanced(s)?.preconditioningState) {
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
    value: (s, _) => switch (egmpAdvanced(s)) {
      final a? when a.hasGear() => TileValue(_gearLetter(a.gear)),
      _ => null,
    },
  ),
  StateTileDefinition(
    id: 'power_state',
    label: 'Power state',
    tier: TileTier.advanced,
    sizes: const [TileSpan(1, 1)],
    value: (s, _) => switch (egmpAdvanced(s)) {
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
  (tileId: 'temperature', span: TileSpan(2, 1)),
  (tileId: 'odometer', span: TileSpan(2, 1)),
  (tileId: 'door_status', span: TileSpan(2, 1)),
  (tileId: 'window_status', span: TileSpan(2, 1)),
];

const egmpBluetoothLayout = <TileLayoutEntry>[
  (tileId: 'battery', span: TileSpan(4, 1)),
  (tileId: 'temperature', span: TileSpan(2, 1)),
  (tileId: 'pack_temperature', span: TileSpan(2, 1)),
  (tileId: 'battery_power', span: TileSpan(4, 2)),
  (tileId: 'pack_voltage', span: TileSpan(1, 1)),
  (tileId: 'gear', span: TileSpan(1, 1)),
  (tileId: 'power_state', span: TileSpan(1, 1)),
  (tileId: 'preconditioning', span: TileSpan(1, 1)),
  (tileId: 'speed', span: TileSpan(1, 1)),
  (tileId: 'odometer', span: TileSpan(1, 1)),
];
