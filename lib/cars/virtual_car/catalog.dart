import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/cars/virtual_car/command_ids.dart';
import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';
import 'package:open_car_app/widgets/tiles/tile_icon.dart';

/// The virtual car's tiles: everything its old dashboard showed.
BasicState _basic(VehicleSnapshot s) => s.basicState as BasicState;

/// The advanced state, only while it is live over this transport.
AdvancedState? _advanced(VehicleSnapshot s) =>
    s.isAdvancedStateLive ? s.advancedState as AdvancedState : null;

/// The speed while the advanced state is live and reports it.
int? virtualCarSpeedKmh(VehicleSnapshot s) {
  final advanced = _advanced(s);
  return advanced != null && advanced.hasSpeed() ? advanced.speed : null;
}

final _speedSeries = HistorySeries(
  id: 'speed',
  sample: (s) => virtualCarSpeedKmh(s)?.toDouble(),
);

String _gearLabel(AdvancedState_Gear gear) => switch (gear) {
  AdvancedState_Gear.GEAR_PARK => 'P',
  AdvancedState_Gear.GEAR_REVERSE => 'R',
  AdvancedState_Gear.GEAR_NEUTRAL => 'N',
  AdvancedState_Gear.GEAR_DRIVE => 'D',
  _ => '?',
};

final virtualCarTiles = <TileDefinition>[
  CommandTileDefinition(
    id: 'doors',
    label: 'Doors',
    tier: TileTier.basic,
    icon: const TileIcon.symbol(Symbols.lock_open, onSymbol: Symbols.lock),
    command: TileCommand(
      key: kDoorLockCommand,
      build: (s) => BasicCommand(
        doorLock: DoorLockCommand(lock: !_basic(s).areDoorsLocked),
      ),
    ),
    state: (s) => !_basic(s).hasAreDoorsLocked()
        ? kUnknownTileState
        : _basic(s).areDoorsLocked
        ? const TileState(on: true, caption: 'Locked')
        : const TileState(on: false, caption: 'Unlocked'),
  ),
  CommandTileDefinition(
    id: 'custom_state_1',
    label: 'Custom 1',
    accessibleLabel: 'Custom state 1',
    tier: TileTier.advanced,
    icon: const TileIcon.symbol(
      Symbols.toggle_off,
      onSymbol: Symbols.toggle_on,
    ),
    command: TileCommand(
      key: kToggleCustomState1Command,
      build: (_) =>
          AdvancedCommand(toggleCustomState1: ToggleCustomState1Command()),
    ),
    state: (s) => switch (_advanced(s)) {
      final a? when a.hasCustomState1() =>
        a.customState1
            ? const TileState(on: true, caption: 'On')
            : const TileState(on: false, caption: 'Off'),
      _ => kUnknownTileState,
    },
  ),
  StateTileDefinition(
    id: 'odometer',
    label: 'Odometer',
    tier: TileTier.basic,
    icon: const TileIcon.symbol(Symbols.speed),
    sizes: const [TileSpan(1, 1), TileSpan(2, 1)],
    value: (s, units) {
      if (!_basic(s).hasOdometer()) return null;
      return TileValue.formatted(
        formatOdometer(_basic(s).odometer, units.distance),
      );
    },
  ),
  StateTileDefinition(
    id: 'driving',
    label: 'Driving',
    tier: TileTier.basic,
    sizes: const [TileSpan(1, 1), TileSpan(2, 1)],
    value: (s, units) => _basic(s).hasIsDriving()
        ? TileValue(_basic(s).isDriving ? 'Yes' : 'No')
        : null,
  ),
  StateTileDefinition(
    id: 'speed',
    label: 'Speed',
    tier: TileTier.advanced,
    history: _speedSeries,
    value: (s, units) {
      final speed = virtualCarSpeedKmh(s);
      if (speed == null) return null;
      return TileValue.formatted(formatSpeed(speed, units.distance));
    },
  ),
  StateTileDefinition(
    id: 'gear',
    label: 'Gear',
    tier: TileTier.advanced,
    sizes: const [TileSpan(1, 1)],
    value: (s, units) => switch (_advanced(s)) {
      final a? when a.hasGear() => TileValue(_gearLabel(a.gear)),
      _ => null,
    },
  ),
  const CarViewTileDefinition(
    id: 'car_view',
    label: 'Car view',
    tier: TileTier.basic,
  ),
];

const virtualCarRemoteLayout = <TileLayoutEntry>[
  (tileId: 'doors', span: TileSpan(2, 1)),
  (tileId: 'driving', span: TileSpan(2, 1)),
  (tileId: 'odometer', span: TileSpan(2, 1)),
];

const virtualCarBluetoothLayout = <TileLayoutEntry>[
  (tileId: 'doors', span: TileSpan(1, 1)),
  (tileId: 'custom_state_1', span: TileSpan(1, 1)),
  (tileId: 'gear', span: TileSpan(1, 1)),
  (tileId: 'driving', span: TileSpan(1, 1)),
  (tileId: 'speed', span: TileSpan(2, 2)),
  (tileId: 'odometer', span: TileSpan(2, 1)),
];
