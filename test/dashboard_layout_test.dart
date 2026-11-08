import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/virtual_car/virtual_car_definition.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/config/saved_layouts_config.dart';
import 'package:open_car_app/models/dashboard_layout.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/providers/dashboard_layout_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

const VehicleDefinition _vehicle = VirtualCarDefinition();
const _small = TileSpan(1, 1);
const _wide = TileSpan(2, 1);

final _config = PairedVehicleConfig(
  vehicleId: _vehicle.platformName,
  bleRemoteId: '',
  transportPreference: TransportPreference.http,
);

final _bluetoothKey = savedLayoutKey(
  _config.storageKey,
  DashboardGrid.bluetooth,
);

TileLayoutEntry _entry(String id, [TileSpan span = _small]) =>
    (tileId: id, span: span);

List<String> _ids(List<TileLayoutEntry> layout) => [
  for (final entry in layout) entry.tileId,
];

TileDefinition _tileOf(TileTier tier, {bool resizable = false}) => _vehicle
    .tiles
    .firstWhere((t) => t.tier == tier && (!resizable || t.sizes.length > 1));

ProviderContainer _container(SavedLayouts saved) {
  final container = ProviderContainer(
    overrides: [
      initialPairedVehicleConfigProvider.overrideWithValue(_config),
      initialSavedLayoutsProvider.overrideWithValue(saved),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('sanitizeLayout', () {
    final basic = _tileOf(TileTier.basic, resizable: true);
    final advanced = _tileOf(TileTier.advanced);

    test('drops a tile the catalog no longer has', () {
      final layout = sanitizeLayout(
        [_entry('gone'), (tileId: basic.id, span: basic.sizes.first)],
        _vehicle,
        DashboardTier.bluetooth,
      );
      expect(_ids(layout), [basic.id]);
    });

    test('does not insert a tile the saved layout lacks', () {
      final saved = [(tileId: basic.id, span: basic.sizes.first)];
      final layout = sanitizeLayout(saved, _vehicle, DashboardTier.bluetooth);
      expect(_ids(layout), [basic.id]);
      expect(
        tilesNotInLayout(
          layout,
          _vehicle,
          DashboardTier.bluetooth,
        ).map((t) => t.id),
        containsAll([
          for (final t in _vehicle.tiles)
            if (t != basic) t.id,
        ]),
      );
    });

    test('drops advanced tiles on the remote tier', () {
      final layout = sanitizeLayout(
        [(tileId: advanced.id, span: advanced.sizes.first)],
        _vehicle,
        DashboardTier.remote,
      );
      expect(layout, isEmpty);
    });

    test('keeps the first of duplicates', () {
      final first = (tileId: basic.id, span: basic.sizes.last);
      final layout = sanitizeLayout(
        [first, (tileId: basic.id, span: basic.sizes.first)],
        _vehicle,
        DashboardTier.bluetooth,
      );
      expect(layout, [first]);
    });

    test('replaces a size the tile no longer supports', () {
      final layout = sanitizeLayout(
        [(tileId: basic.id, span: const TileSpan(3, 3))],
        _vehicle,
        DashboardTier.bluetooth,
      );
      expect(layout.single.span, basic.sizes.first);
    });
  });

  test('tilesNotInLayout leaves advanced tiles out on the remote tier', () {
    final tiles = tilesNotInLayout(const [], _vehicle, DashboardTier.remote);
    expect(tiles, isNotEmpty);
    expect(tiles.where((t) => t.tier == TileTier.advanced), isEmpty);
  });

  group('edits', () {
    final layout = [_entry('a'), _entry('b'), _entry('c')];

    test('remove', () {
      expect(_ids(layout.withoutTile('b')), ['a', 'c']);
    });

    test('add goes last, at the first size', () {
      final tile = _tileOf(TileTier.basic, resizable: true);
      expect(layout.withTile(tile).last, (
        tileId: tile.id,
        span: tile.sizes.first,
      ));
    });

    test('move earlier and later', () {
      expect(_ids(layout.withTileMoved('b', -1)), ['b', 'a', 'c']);
      expect(_ids(layout.withTileMoved('b', 1)), ['a', 'c', 'b']);
    });

    test('a move past either end stops there', () {
      expect(_ids(layout.withTileMoved('a', -1)), ['a', 'b', 'c']);
      expect(_ids(layout.withTileMoved('c', 1)), ['a', 'b', 'c']);
    });

    test('moving an unknown tile changes nothing', () {
      expect(layout.withTileMoved('nope', 1), layout);
    });

    test('the next size wraps around', () {
      final tile = _tileOf(TileTier.basic, resizable: true);
      var edited = [(tileId: tile.id, span: tile.sizes.first)];
      for (final size in [...tile.sizes.skip(1), tile.sizes.first]) {
        edited = edited.withNextSize(tile);
        expect(edited.single.span, size);
      }
    });
  });

  group('persistence', () {
    test('a layout survives a restart', () async {
      final layout = [_entry('doors', _wide), _entry('speed')];
      await saveLayout('virtual_car/bluetooth', layout);
      expect(await loadSavedLayouts(), {'virtual_car/bluetooth': layout});
    });

    test('an edited empty layout stays empty', () async {
      await saveLayout('virtual_car/bluetooth', const []);
      expect(await loadSavedLayouts(), {
        'virtual_car/bluetooth': const <TileLayoutEntry>[],
      });
    });

    test('a corrupt layout is skipped, others load', () async {
      SharedPreferences.setMockInitialValues({
        'dashboard_layout/virtual_car/remote': 'not json',
        'dashboard_layout/egmp/remote': '[{"id":"a","columns":0,"rows":1}]',
        'dashboard_layout/virtual_car/bluetooth':
            '[{"id":"a","columns":1,"rows":1}]',
        'theme_mode': 'dark',
      });
      expect(await loadSavedLayouts(), {
        'virtual_car/bluetooth': [_entry('a')],
      });
    });

    test('clearing removes it', () async {
      await saveLayout('virtual_car/bluetooth', [_entry('a')]);
      await clearLayout('virtual_car/bluetooth');
      expect(await loadSavedLayouts(), isEmpty);
    });
  });

  group('dashboardLayoutProvider', () {
    const tier = DashboardTier.bluetooth;
    final provider = dashboardLayoutProvider(tier);
    final tile = _tileOf(TileTier.basic);
    final saved = [(tileId: tile.id, span: tile.sizes.first)];

    test('gives the default with nothing saved', () {
      expect(_container({}).read(provider), _vehicle.defaultLayout(tier));
    });

    test('gives the saved layout, cleaned up', () {
      final container = _container({
        _bluetoothKey: [_entry('gone'), ...saved],
      });
      expect(container.read(provider), saved);
    });

    test('saves per grid and persists', () async {
      final container = _container({});
      container
          .read(savedLayoutsProvider.notifier)
          .save(DashboardGrid.bluetooth, saved);
      expect(container.read(provider), saved);
      expect(
        container.read(dashboardLayoutProvider(DashboardTier.remote)),
        _vehicle.defaultLayout(DashboardTier.remote),
      );
      await pumpEventQueue();
      expect(await loadSavedLayouts(), {_bluetoothKey: saved});
    });

    test('reset goes back to the default and forgets it', () async {
      final container = _container({});
      final notifier = container.read(savedLayoutsProvider.notifier);
      notifier.save(DashboardGrid.bluetooth, saved);
      await pumpEventQueue();
      notifier.reset(DashboardGrid.bluetooth);
      expect(container.read(provider), _vehicle.defaultLayout(tier));
      await pumpEventQueue();
      expect(await loadSavedLayouts(), isEmpty);
    });
  });

  test('only the Bluetooth grid is editable for now', () {
    expect(
      DashboardGrid.of(DashboardTier.remote).editing,
      TileGridEditing.none,
    );
    expect(
      DashboardGrid.of(DashboardTier.bluetooth).editing,
      TileGridEditing.explicit,
    );
  });
}
