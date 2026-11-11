import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/virtual_car/virtual_car_definition.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/models/vehicle_summary.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/providers/vehicle_summary_provider.dart';
import 'package:open_car_app/screens/dashboard/dashboard_header.dart';
import 'package:open_car_app/screens/vehicles_screen.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/vehicle_list_parts.dart';

const _platform = VirtualCarDefinition();

PairedVehicleConfig _vehicle(String id, {String? name}) => PairedVehicleConfig(
  id: id,
  name: name,
  vehicleId: _platform.platformName,
  bleRemoteId: id.toUpperCase(),
  transportPreference: TransportPreference.ble,
);

final _ev6 = _vehicle('ev6', name: 'EV6');
final _city = _vehicle('city', name: 'City car');

class _Transport implements CarTransport {
  const _Transport(this.transportType);

  @override
  final TransportType transportType;
  @override
  Stream<DeviceToApp> get messages => const Stream.empty();
  @override
  Future<void> send(AppToDevice message) async {}
  @override
  void dispose() {}
}

class _FakeState extends VehicleStateNotifier {
  _FakeState({required this.live});

  final bool live;

  @override
  VehicleSnapshot build() => VehicleSnapshot(
    basicState: BasicState(),
    advancedState: AdvancedState(),
    isStateLive: live,
  );
}

void main() {
  late ProviderContainer container;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  PairedVehicles paired() => container.read(pairedVehiclesProvider);

  /// Shows [home] with [vehicles] paired, the first one current and live
  /// over [link].
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    required List<PairedVehicleConfig> vehicles,
    TransportType link = TransportType.mqtt,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    container = ProviderContainer(
      overrides: [
        initialPairedVehiclesProvider.overrideWithValue(
          PairedVehicles(vehicles: vehicles, currentId: vehicles.first.id),
        ),
        initialVehicleSummariesProvider.overrideWithValue({
          'ev6': const VehicleSummary(
            levelPercent: 64,
            rangeKm: 312,
            distanceUnit: DistanceUnit.kilometers,
          ),
          'city': VehicleSummary(
            levelPercent: 88,
            rangeKm: 214,
            distanceUnit: DistanceUnit.kilometers,
            lastUpdated: now.subtract(const Duration(hours: 3)),
          ),
        }),
        carTransportProvider.overrideWithValue(_Transport(link)),
        vehicleStateProvider.overrideWith(() => _FakeState(live: true)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(defaultSkin, Brightness.light),
          home: home,
        ),
      ),
    );
  }

  group('vehicle status line', () {
    test('shows the level, the range and the state', () {
      expect(
        vehicleStatusLine(
          const VehicleSummary(levelPercent: 64, rangeKm: 312),
          state: 'Remote',
        ),
        '64% · 312 km · Remote',
      );
    });

    test('shows the range in the car\'s unit', () {
      expect(
        vehicleStatusLine(
          const VehicleSummary(
            levelPercent: 41,
            rangeKm: 380,
            distanceUnit: DistanceUnit.miles,
          ),
          state: 'Updated 3 h ago',
        ),
        '41% · 236 mi · Updated 3 h ago',
      );
    });

    test('leaves out what is not known', () {
      final now = DateTime.now();
      expect(
        vehicleStatusLine(null, state: idleVehicleState(null, now)),
        'Not updated yet',
      );
    });
  });

  group('switcher', () {
    const header = Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            VehicleNameButton(name: 'EV6', style: TextStyle(fontSize: 28)),
          ],
        ),
      ),
    );

    Future<void> open(
      WidgetTester tester, {
      required List<PairedVehicleConfig> vehicles,
    }) async {
      await pump(tester, header, vehicles: vehicles);
      await tester.tap(find.text('EV6'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists each vehicle with its state, the current one checked', (
      tester,
    ) async {
      await open(tester, vehicles: [_ev6, _city]);

      expect(find.text('64% · 312 km · Remote'), findsOneWidget);
      expect(find.text('City car'), findsOneWidget);
      expect(find.text('88% · 214 km · Updated 3 h ago'), findsOneWidget);
      expect(find.byType(VehicleAvatar), findsNWidgets(2));
      expect(find.bySemanticsLabel('EV6, current vehicle'), findsOneWidget);
      expect(find.bySemanticsLabel('Switch to City car'), findsOneWidget);
      expect(find.text('Add a vehicle'), findsOneWidget);
      expect(find.text('Manage vehicles'), findsOneWidget);
    });

    testWidgets('opens with a single vehicle, to add a second', (tester) async {
      await open(tester, vehicles: [_ev6]);

      expect(find.byType(VehicleAvatar), findsOneWidget);
      expect(find.text('Add a vehicle'), findsOneWidget);
      expect(find.text('Manage vehicles'), findsOneWidget);
    });

    testWidgets('tapping another vehicle switches to it and closes', (
      tester,
    ) async {
      await open(tester, vehicles: [_ev6, _city]);

      await tester.tap(find.text('City car'));
      await tester.pumpAndSettle();

      expect(paired().currentId, 'city');
      expect(find.text('Manage vehicles'), findsNothing);
    });

    testWidgets('tapping the current vehicle only closes', (tester) async {
      await open(tester, vehicles: [_ev6, _city]);

      await tester.tap(find.text('64% · 312 km · Remote'));
      await tester.pumpAndSettle();

      expect(paired().currentId, 'ev6');
      expect(find.text('Manage vehicles'), findsNothing);
    });

    testWidgets('Manage vehicles opens the Vehicles screen', (tester) async {
      await open(tester, vehicles: [_ev6, _city]);

      await tester.tap(find.text('Manage vehicles'));
      await tester.pumpAndSettle();

      expect(find.byType(VehiclesScreen), findsOneWidget);
    });
  });

  group('Vehicles screen', () {
    testWidgets('has a card per vehicle, the current one badged', (
      tester,
    ) async {
      await pump(tester, const VehiclesScreen(), vehicles: [_ev6, _city]);

      expect(find.text('EV6'), findsOneWidget);
      expect(find.text('City car'), findsOneWidget);
      expect(find.text(_platform.platformLabel), findsNWidgets(2));
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Rename'), findsNWidgets(2));
      expect(find.text('Unpair'), findsNWidgets(2));
      expect(find.text('Add a vehicle'), findsOneWidget);
    });

    testWidgets('tapping another vehicle makes it current', (tester) async {
      await pump(tester, const VehiclesScreen(), vehicles: [_ev6, _city]);

      await tester.tap(find.text('City car'));
      await tester.pumpAndSettle();

      expect(paired().currentId, 'city');
    });

    testWidgets('renames a vehicle, and a blank name goes back to the '
        'platform\'s', (tester) async {
      await pump(tester, const VehiclesScreen(), vehicles: [_ev6, _city]);

      await tester.tap(find.bySemanticsLabel('Rename City car'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Weekend car ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Weekend car'), findsOneWidget);
      expect(paired().vehicles.last.name, 'Weekend car');

      await tester.tap(find.bySemanticsLabel('Rename Weekend car'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(paired().vehicles.last.name, isNull);
      expect(find.text(_platform.displayName), findsOneWidget);
    });

    testWidgets('unpairing one of several says the others stay', (
      tester,
    ) async {
      await pump(tester, const VehiclesScreen(), vehicles: [_ev6, _city]);

      await tester.tap(find.bySemanticsLabel('Unpair City car'));
      await tester.pumpAndSettle();

      expect(find.text('Unpair City car?'), findsOneWidget);
      expect(
        find.text(
          'City car will be removed from this app. To use it again, put the '
          'device in pairing mode and pair again.\n\n'
          'Your other vehicles are not affected.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Unpair'));
      await tester.pumpAndSettle();

      expect(paired().vehicles.map((v) => v.id), ['ev6']);
      expect(find.byType(VehiclesScreen), findsOneWidget);
      expect(find.text('City car'), findsNothing);
    });

    testWidgets('cancelling keeps the vehicle', (tester) async {
      await pump(tester, const VehiclesScreen(), vehicles: [_ev6, _city]);

      await tester.tap(find.bySemanticsLabel('Unpair City car'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(paired().vehicles, hasLength(2));
    });

    testWidgets('unpairing the last vehicle leaves out the others and closes '
        'the screen', (tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => VehiclesScreen.open(context),
              child: const Text('Open'),
            ),
          ),
        ),
        vehicles: [_ev6],
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Unpair EV6'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'EV6 will be removed from this app. To use it again, put the device '
          'in pairing mode and pair again.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Unpair'));
      await tester.pumpAndSettle();

      expect(paired().vehicles, isEmpty);
      expect(find.byType(VehiclesScreen), findsNothing);
    });
  });
}
