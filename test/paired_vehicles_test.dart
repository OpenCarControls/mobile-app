import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/virtual_car/virtual_car_definition.dart';
import 'package:open_car_app/config/connection_activity_config.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/config/saved_layouts_config.dart';
import 'package:open_car_app/config/unsupported_commands_config.dart';
import 'package:open_car_app/config/vehicle_state_cache_config.dart';
import 'package:open_car_app/models/connection_activity.dart';
import 'package:open_car_app/models/dashboard_layout.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/connection_activity_provider.dart';
import 'package:open_car_app/providers/dashboard_layout_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_summary_provider.dart';

const _vehicleDefinition = VirtualCarDefinition();

PairedVehicleConfig _vehicle(String id, {String? name}) => PairedVehicleConfig(
  id: id,
  name: name,
  vehicleId: _vehicleDefinition.platformName,
  bleRemoteId: id.toUpperCase(),
  transportPreference: TransportPreference.ble,
);

ProviderContainer _container(
  List<PairedVehicleConfig> vehicles, {
  String? currentId,
  List overrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      initialPairedVehiclesProvider.overrideWithValue(
        PairedVehicles(vehicles: vehicles, currentId: currentId),
      ),
      ...overrides.cast(),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

extension on ProviderContainer {
  PairedVehiclesNotifier get paired => read(pairedVehiclesProvider.notifier);
  String? get currentId => read(pairedVehicleProvider)?.id;
  List<String> get ids => [
    for (final vehicle in read(pairedVehiclesProvider).vehicles) vehicle.id,
  ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('pairing', () {
    test('a new vehicle is added and becomes current', () async {
      final c = _container([_vehicle('a')], currentId: 'a');

      await c.paired.pair(_vehicle('b'));

      expect(c.ids, ['a', 'b']);
      expect(c.currentId, 'b');
      expect((await PairedVehicles.load()).current?.id, 'b');
    });

    test('the first vehicle becomes current', () async {
      final c = _container(const []);
      await c.paired.pair(_vehicle('a'));
      expect(c.currentId, 'a');
    });

    test('pairing a device again keeps its entry, id and name', () async {
      final c = _container([
        _vehicle('a', name: 'Mine'),
        _vehicle('b'),
      ], currentId: 'b');

      await c.paired.pair(
        PairedVehicleConfig(
          id: 'new',
          vehicleId: _vehicleDefinition.platformName,
          bleRemoteId: 'A',
          transportPreference: TransportPreference.ble,
        ),
      );

      expect(c.ids, ['a', 'b']);
      expect(c.currentId, 'a');
      expect(c.read(pairedVehicleProvider)?.name, 'Mine');
    });

    test('two vehicles of the same platform stay apart', () async {
      final c = _container(const []);
      await c.paired.pair(_vehicle('a'));
      await c.paired.pair(_vehicle('b'));

      final vehicles = c.read(pairedVehiclesProvider).vehicles;
      expect(vehicles.map((v) => v.storageKey).toSet(), hasLength(2));
    });
  });

  group('switching', () {
    test('the providers follow the current vehicle', () async {
      final c = _container([_vehicle('a'), _vehicle('b')], currentId: 'a');
      expect(c.currentId, 'a');

      await c.paired.switchTo('b');

      expect(c.currentId, 'b');
      expect(c.read(selectedVehicleProvider), isNotNull);
      expect((await PairedVehicles.load()).current?.id, 'b');
    });

    test('an unknown vehicle is ignored', () async {
      final c = _container([_vehicle('a')], currentId: 'a');
      await c.paired.switchTo('nope');
      expect(c.currentId, 'a');
    });

    test('each vehicle has its own layout', () async {
      const tier = DashboardTier.bluetooth;
      final defaults = _vehicleDefinition.defaultLayout(tier);
      expect(defaults.length, greaterThan(1));
      final c = _container(
        [_vehicle('a'), _vehicle('b')],
        currentId: 'a',
        overrides: [
          initialSavedLayoutsProvider.overrideWithValue({
            savedLayoutKey('a', DashboardGrid.of(tier)): defaults
                .take(1)
                .toList(),
          }),
        ],
      );
      expect(c.read(dashboardLayoutProvider(tier)), hasLength(1));

      await c.paired.switchTo('b');
      expect(c.read(dashboardLayoutProvider(tier)), hasLength(defaults.length));

      await c.paired.switchTo('a');
      expect(c.read(dashboardLayoutProvider(tier)), hasLength(1));
    });
  });

  group('names', () {
    test('a vehicle shows its platform name until renamed', () async {
      final c = _container([_vehicle('a')], currentId: 'a');
      expect(
        c.read(currentVehicleNameProvider),
        _vehicleDefinition.displayName,
      );

      await c.paired.rename('a', '  Mine ');
      expect(c.read(currentVehicleNameProvider), 'Mine');
      expect((await PairedVehicles.load()).current?.name, 'Mine');
    });

    test('a blank name goes back to the platform name', () async {
      final c = _container([_vehicle('a', name: 'Mine')], currentId: 'a');

      await c.paired.rename('a', '   ');

      expect(c.read(pairedVehicleProvider)?.name, isNull);
      expect(
        c.read(currentVehicleNameProvider),
        _vehicleDefinition.displayName,
      );
    });
  });

  group('unpairing', () {
    test('another vehicle leaves the current one alone', () async {
      final c = _container([_vehicle('a'), _vehicle('b')], currentId: 'a');

      await c.paired.unpair('b');

      expect(c.ids, ['a']);
      expect(c.currentId, 'a');
    });

    test('the current vehicle falls back to the first remaining', () async {
      final c = _container([
        _vehicle('a'),
        _vehicle('b'),
        _vehicle('c'),
      ], currentId: 'b');

      await c.paired.unpair();

      expect(c.ids, ['a', 'c']);
      expect(c.currentId, 'a');
      expect((await PairedVehicles.load()).current?.id, 'a');
    });

    test('the last vehicle leaves nothing paired', () async {
      final c = _container([_vehicle('a')], currentId: 'a');

      await c.paired.unpair();

      expect(c.ids, isEmpty);
      expect(c.read(pairedVehicleProvider), isNull);
      expect(c.read(selectedVehicleProvider), isNull);
      expect((await PairedVehicles.load()).vehicles, isEmpty);
    });

    test('deletes what was stored for that vehicle only', () async {
      final grid = DashboardGrid.of(DashboardTier.bluetooth);
      final layout = _vehicleDefinition
          .defaultLayout(DashboardTier.bluetooth)
          .take(1)
          .toList();
      final entries = [
        ConnectionChangeEntry(DateTime(2026), ConnectionChange.remoteConnected),
      ];
      final prefs = await SharedPreferences.getInstance();
      for (final key in ['a', 'b']) {
        await saveLayout(savedLayoutKey(key, grid), layout);
        await saveUnsupportedCommands(key, {'basic/1'});
        await saveConnectionActivity(key, entries);
        await prefs.setString(
          '$kVehicleStateCachePrefix$key',
          '{"lastUpdated":"2026-01-01T00:00:00Z"}',
        );
      }
      final c = _container(
        [_vehicle('a'), _vehicle('b')],
        currentId: 'a',
        overrides: [
          initialSavedLayoutsProvider.overrideWithValue(
            await loadSavedLayouts(),
          ),
          initialUnsupportedCommandsProvider.overrideWithValue(
            await loadUnsupportedCommands(),
          ),
          initialConnectionActivityProvider.overrideWithValue(
            await loadConnectionActivity(),
          ),
          initialVehicleSummariesProvider.overrideWithValue(
            await loadVehicleSummaries(),
          ),
        ],
      );

      await c.paired.unpair('a');

      expect(await loadSavedLayouts(), {savedLayoutKey('b', grid): isNotEmpty});
      expect((await loadUnsupportedCommands()).keys, ['b']);
      expect((await loadConnectionActivity()).keys, ['b']);
      expect((await loadVehicleSummaries()).keys, ['b']);
      expect(c.read(savedLayoutsProvider).keys, [savedLayoutKey('b', grid)]);
      expect(c.read(unsupportedCommandsProvider).keys, ['b']);
      expect(c.read(connectionActivityLogsProvider).keys, ['b']);
      expect(c.read(vehicleSummariesProvider).keys, ['b']);
    });
  });
}
