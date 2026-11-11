import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:protobuf/protobuf.dart';

import 'package:open_car_app/cars/egmp/egmp_definition.dart';
import 'package:open_car_app/cars/egmp/units.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/widgets/tiles/catalog_tile.dart';
import 'package:open_car_app/widgets/tiles/command_control.dart';
import 'package:open_car_app/widgets/tiles/tile_context.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';
import 'package:open_car_app/widgets/tiles/tile_icon.dart';

const _lock = (set: CommandSet.basic, id: 1);
const _climateKey = (set: CommandSet.basic, id: 4);

BasicState _basic(VehicleSnapshot s) => s.basicState as BasicState;

final _doors = CommandTileDefinition(
  id: 'doors',
  label: 'Doors',
  tier: TileTier.basic,
  icon: const TileIcon.symbol(Symbols.lock),
  command: TileCommand(
    key: _lock,
    build: (s) => BasicCommand(
      doorLockCommand: DoorLockCommand(lock: !_basic(s).areDoorsLocked),
    ),
    activityName: (_) => 'Lock doors',
  ),
  state: (s) => _basic(s).areDoorsLocked
      ? const TileState(on: true, caption: 'Locked')
      : const TileState(on: false, caption: 'Unlocked'),
);

final _odometerSeries = HistorySeries(
  id: 'odometer',
  sample: (s) => _basic(s).odometer.toDouble(),
);

final _odometer = StateTileDefinition(
  id: 'odometer',
  label: 'Odometer',
  tier: TileTier.basic,
  history: _odometerSeries,
  value: (s, units) => _basic(s).hasOdometer()
      ? TileValue('${_basic(s).odometer}', unit: 'km')
      : null,
);

final _battery = EnergyDescription(
  kind: EnergyKind.battery,
  levelPercent: (s) => _basic(s).hasBatterySoc() ? _basic(s).batterySoc : null,
  rangeKm: (s) =>
      _basic(s).hasBatteryRangeKm() ? _basic(s).batteryRangeKm : null,
  status: (s) => switch (_basic(s).chargePortState) {
    BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING => EnergyStatus(
      flow: EnergyFlow.charging,
      powerWatts: _basic(s).powerFlowWatt,
      limitPercent: 80,
      timeToLimitMinutes: 65,
    ),
    BasicState_ChargePortState.CHARGE_PORT_STATE_V2L_ACTIVE => EnergyStatus(
      flow: EnergyFlow.exporting,
      powerWatts: -_basic(s).powerFlowWatt,
    ),
    _ => const EnergyStatus(limitPercent: 80),
  },
);

final _climate = ClimateDescription(
  command: _climateKey,
  isOn: (s) => _basic(s).isClimateOn,
  insideCelsius: (s) => _basic(s).indoorTemperature,
  outsideCelsius: (s) => _basic(s).outdoorTemperature,
  targetCelsius: (s) => _basic(s).hasTargetClimateTemperature()
      ? _basic(s).targetClimateTemperature
      : null,
  minCelsius: 17,
  maxCelsius: 27,
  stepCelsius: 0.5,
  formatTarget: formatEgmpClimateTarget,
  power: (s, on) =>
      BasicCommand(climateControlCommand: ClimateControlCommand(climateOn: on)),
  setTarget: (s, c) => BasicCommand(
    climateControlCommand: ClimateControlCommand(
      climateOn: true,
      targetTemperature: c,
    ),
  ),
  extras: [
    LeveledClimateExtra(
      id: 'driver_seat',
      label: 'Driver seat heating',
      icon: const TileIcon.symbol(Symbols.seat_heat_left),
      side: ClimateSide.left,
      levels: 3,
      level: (s) => 2,
      next: (level) => 1,
      command: (s, level) => BasicCommand(),
    ),
  ],
);

final _tiles = <TileDefinition>[
  _doors,
  _odometer,
  EnergyTileDefinition(
    id: 'battery',
    label: 'Battery',
    tier: TileTier.basic,
    energy: _battery,
  ),
  ClimateTileDefinition(
    id: 'climate',
    label: 'Climate',
    tier: TileTier.basic,
    climate: _climate,
  ),
  ChartTileDefinition(
    id: 'power',
    label: 'Power',
    tier: TileTier.advanced,
    series: const [],
    describe: (data) => '7.2 kilowatts',
    builder: (context, data) => const Text('chart'),
  ),
  CustomTileDefinition(
    id: 'custom',
    label: 'Custom',
    tier: TileTier.basic,
    sizes: const [TileSpan(2, 1)],
    describe: (data) => 'odometer ${_basic(data.snapshot).odometer}',
    builder: (context, data) => Text('Drawn ${data.span.columns} wide'),
  ),
];

class _TestCar extends EgmpDefinition {
  const _TestCar();

  @override
  List<TileDefinition> get tiles => _tiles;

  @override
  List<EnergyDescription> get energy => [_battery];

  @override
  ClimateDescription? get climate => _climate;
}

VehicleSnapshot _snapshot(BasicState basic) =>
    VehicleSnapshot(basicState: basic, advancedState: AdvancedState());

void main() {
  late List<(CommandKey, GeneratedMessage)> sent;

  setUp(() => sent = []);

  Future<void> pump(
    WidgetTester tester,
    BasicState basic, {
    required String tileId,
    TileSpan span = const TileSpan(1, 1),
    bool iconOnly = false,
  }) async {
    final data = TileContext(
      vehicle: const _TestCar(),
      snapshot: _snapshot(basic),
      iconOnly: iconOnly,
    );
    final tile = _tiles.firstWhere((t) => t.id == tileId);
    final shown = tile.spanFor(span, data.snapshot);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          commandUiStateProvider.overrideWith(
            (ref, key) => CommandUiState.enabled,
          ),
          tileCommandSenderProvider.overrideWithValue((key, message) async {
            sent.add((key, message));
            return null;
          }),
        ],
        child: MaterialApp(
          theme: buildAppTheme(defaultSkin, Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: shown.columns * 90.0,
                height: shown.rows * 72.0,
                child: CatalogTile(tile: tile, span: shown, data: data),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('command tile', () {
    testWidgets('announces its state and sends the built command', (
      tester,
    ) async {
      await pump(tester, BasicState(areDoorsLocked: true), tileId: 'doors');
      expect(find.bySemanticsLabel('Doors, locked'), findsOneWidget);
      expect(find.text('Doors'), findsOneWidget);
      expect(find.text('Locked'), findsNothing);

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(sent.single.$1, _lock);
      expect((sent.single.$2 as BasicCommand).doorLockCommand.lock, isFalse);
    });

    testWidgets('shows a caption at 2×1', (tester) async {
      await pump(
        tester,
        BasicState(areDoorsLocked: false),
        tileId: 'doors',
        span: const TileSpan(2, 1),
      );
      expect(find.text('Unlocked'), findsOneWidget);
    });

    testWidgets('icon-only keeps its label for screen readers', (tester) async {
      await pump(tester, BasicState(), tileId: 'doors', iconOnly: true);
      expect(find.text('Doors'), findsNothing);
      expect(find.bySemanticsLabel('Doors, unlocked'), findsOneWidget);
    });
  });

  testWidgets('a custom tile draws itself and describes its values', (
    tester,
  ) async {
    await pump(
      tester,
      BasicState(odometer: 12),
      tileId: 'custom',
      span: const TileSpan(2, 1),
    );
    expect(find.text('Drawn 2 wide'), findsOneWidget);
    expect(find.bySemanticsLabel('Custom, odometer 12'), findsOneWidget);
  });

  group('state tile', () {
    testWidgets('announces its value', (tester) async {
      await pump(tester, BasicState(odometer: 22916), tileId: 'odometer');
      expect(find.bySemanticsLabel('Odometer, 22916 km'), findsOneWidget);
    });

    testWidgets('shows a dash for an unknown value', (tester) async {
      await pump(
        tester,
        BasicState(),
        tileId: 'odometer',
        span: const TileSpan(2, 2),
      );
      expect(find.bySemanticsLabel('Odometer, unknown'), findsOneWidget);
    });
  });

  group('energy tile', () {
    testWidgets('idle: level and range', (tester) async {
      await pump(
        tester,
        BasicState(batterySoc: 64, batteryRangeKm: 312),
        tileId: 'battery',
        span: const TileSpan(4, 1),
      );
      expect(find.text('64% · 312 km'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Battery, 64 percent, 312 km, limit 80 percent'),
        findsOneWidget,
      );
    });

    testWidgets('charging: power and time to the limit', (tester) async {
      await pump(
        tester,
        BasicState(
          batterySoc: 64,
          chargePortState:
              BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING,
          powerFlowWatt: 7200,
        ),
        tileId: 'battery',
        span: const TileSpan(4, 1),
      );
      expect(find.text('Charging · 7.2 kW'), findsOneWidget);
      expect(find.text('1 h 5 min to 80%'), findsOneWidget);
    });

    testWidgets('exporting: power out', (tester) async {
      await pump(
        tester,
        BasicState(
          batterySoc: 64,
          chargePortState:
              BasicState_ChargePortState.CHARGE_PORT_STATE_V2L_ACTIVE,
          powerFlowWatt: -1800,
        ),
        tileId: 'battery',
        span: const TileSpan(4, 1),
      );
      expect(find.text('Exporting · 1.8 kW'), findsOneWidget);
    });
  });

  group('climate tile', () {
    testWidgets('off: only the bar', (tester) async {
      final basic = BasicState(
        isClimateOn: false,
        indoorTemperature: 19.5,
        outdoorTemperature: 12,
      );
      expect(
        _tiles[3].spanFor(const TileSpan(4, 1), _snapshot(basic)),
        const TileSpan(4, 1),
      );
      await pump(tester, basic, tileId: 'climate', span: const TileSpan(4, 1));
      expect(find.text('Inside 19.5°C · Outside 12.0°C'), findsOneWidget);
      expect(find.bySemanticsLabel('Climate, off'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Warmer')), findsNothing);
    });

    testWidgets('on: grows, steps the target, shows the extras', (
      tester,
    ) async {
      final basic = BasicState(isClimateOn: true, targetClimateTemperature: 21);
      expect(
        _tiles[3].spanFor(const TileSpan(4, 1), _snapshot(basic)),
        ClimateTileDefinition.onSpan,
      );
      await pump(tester, basic, tileId: 'climate', span: const TileSpan(4, 1));
      expect(find.text('21.0°'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Driver seat heating, level 2 of 3'),
        findsOneWidget,
      );
      expect(find.text('L'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Warmer, target 21.0°'));
      await tester.pumpAndSettle();
      final command = (sent.single.$2 as BasicCommand).climateControlCommand;
      expect(command.targetTemperature, 21.5);
    });

    testWidgets('names what each button does for the activity log', (
      tester,
    ) async {
      await pump(
        tester,
        BasicState(isClimateOn: true, targetClimateTemperature: 21),
        tileId: 'climate',
        span: const TileSpan(4, 1),
      );
      String activity(String semanticLabel) => tester
          .widgetList<CommandControl>(find.byType(CommandControl))
          .firstWhere((control) => control.semanticLabel == semanticLabel)
          .activityName;

      expect(activity('Climate, on'), 'Climate off');
      expect(activity('Warmer, target 21.0°'), 'Set temperature to 21.5°');
      expect(activity('Colder, target 21.0°'), 'Set temperature to 20.5°');
      expect(
        activity('Driver seat heating, level 2 of 3'),
        'Driver seat heating level 1',
      );
    });

    testWidgets('can\'t step past the range', (tester) async {
      await pump(
        tester,
        BasicState(isClimateOn: true, targetClimateTemperature: 27),
        tileId: 'climate',
      );
      await tester.tap(find.bySemanticsLabel('Warmer, target 27.0°'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
    });
  });

  testWidgets('chart tiles announce their description', (tester) async {
    await pump(
      tester,
      BasicState(),
      tileId: 'power',
      span: const TileSpan(2, 2),
    );
    expect(find.bySemanticsLabel('Power, 7.2 kilowatts'), findsOneWidget);
  });

  test('grid items leave out other tiers and grow the climate tile', () {
    final data = TileContext(
      vehicle: const _TestCar(),
      snapshot: _snapshot(BasicState(isClimateOn: true)),
    );
    final items = catalogGridItems(
      [
        (tileId: 'doors', span: const TileSpan(1, 1)),
        (tileId: 'climate', span: const TileSpan(4, 1)),
        (tileId: 'power', span: const TileSpan(2, 2)),
        (tileId: 'gone', span: const TileSpan(1, 1)),
      ],
      data,
      tiers: {TileTier.basic},
    );
    expect([for (final item in items) item.id], ['doors', 'climate']);
    expect(items[1].span, ClimateTileDefinition.onSpan);
  });
}
