import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/virtual_car/constants.g.dart' as virtual_car;
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/screens/dashboard/dashboard_header.dart';
import 'package:open_car_app/screens/dashboard/dashboard_screen.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/stale_values.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

class _FakeTransport implements CarTransport {
  _FakeTransport(this.transportType);

  final _controller = StreamController<DeviceToApp>.broadcast();

  void emit(DeviceToApp msg) => _controller.add(msg);

  @override
  final TransportType transportType;

  @override
  Stream<DeviceToApp> get messages => _controller.stream;

  @override
  Future<void> send(AppToDevice message) async {}

  @override
  void dispose() => _controller.close();
}

class _TypeNotifier extends Notifier<TransportType> {
  _TypeNotifier(this._initial);

  final TransportType _initial;

  @override
  TransportType build() => _initial;

  void set(TransportType type) => state = type;
}

const _config = PairedVehicleConfig(
  vehicleId: virtual_car.kPlatformName,
  bleRemoteId: '00:11:22:33:44:55',
  transportPreference: TransportPreference.ble,
);

DeviceToApp _liveState() => DeviceToApp(
  platformId: virtual_car.kPlatformId,
  stateUpdate: StateUpdate(
    vehicleState: VehicleState(
      basicStateBytes: BasicState(
        odometer: 1234,
        areDoorsLocked: true,
      ).writeToBuffer(),
    ),
  ),
);

const _heroBox = Key('dashboard-hero-box');

/// The dashboard of the virtual car on a 400×800 phone, over transports the
/// test can switch between.
class _Harness {
  _Harness(this.tester);

  final WidgetTester tester;
  final transports = {
    for (final type in [TransportType.ble, TransportType.mqtt])
      type: _FakeTransport(type),
  };
  late final _TypeNotifier _type;

  _FakeTransport get transport =>
      transports[_type.state] ?? transports[TransportType.ble]!;

  Future<void> pump({
    TransportType type = TransportType.ble,
    double textScale = 1,
    double height = 800,
  }) async {
    tester.view.physicalSize = Size(400, height);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final t in transports.values) {
      addTearDown(t.dispose);
    }
    _type = _TypeNotifier(type);
    final typeProvider = NotifierProvider<_TypeNotifier, TransportType>(
      () => _type,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
          initialPairedVehicleConfigProvider.overrideWithValue(_config),
          carTransportProvider.overrideWith(
            (ref) => transports[ref.watch(typeProvider)]!,
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(defaultSkin, Brightness.light),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> switchTo(TransportType type) async {
    _type.set(type);
    await tester.pumpAndSettle();
  }

  /// Ends the test's providers, which cancels the state liveness timer.
  Future<void> dispose() => tester.pumpWidget(const SizedBox());
}

double _opacityOf(WidgetTester tester, Finder text) {
  final dimmed = find.ancestor(of: text, matching: find.byType(StaleDimmed));
  final opacity = find.descendant(
    of: dimmed.first,
    matching: find.byType(AnimatedOpacity),
  );
  return tester.widget<AnimatedOpacity>(opacity.first).opacity;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the tier follows the transport', () {
    expect(dashboardTierFor(TransportType.mqtt).name, 'remote');
    for (final type in [
      TransportType.ble,
      TransportType.stub,
      TransportType.http,
    ]) {
      expect(dashboardTierFor(type).name, 'bluetooth');
    }
  });

  testWidgets('switches between the Bluetooth and remote tiers', (
    tester,
  ) async {
    final harness = _Harness(tester);
    await harness.pump();

    // Bluetooth: no hero, advanced tiles.
    expect(find.byKey(_heroBox), findsNothing);
    expect(find.text('Custom 1'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);

    harness.transport.emit(_liveState());
    await tester.pumpAndSettle();
    expect(find.text('Bluetooth'), findsOneWidget);

    await harness.switchTo(TransportType.mqtt);
    // Remote: the hero, and basic tiles only.
    expect(find.byKey(_heroBox), findsOneWidget);
    expect(find.text('Custom 1'), findsNothing);

    harness.transport.emit(_liveState());
    await tester.pumpAndSettle();
    expect(find.text('Remote'), findsOneWidget);

    await harness.switchTo(TransportType.ble);
    expect(find.byKey(_heroBox), findsNothing);
    await harness.dispose();
  });

  group('the remote hero box', () {
    testWidgets('fills the space between the header and the tiles', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.pump(type: TransportType.mqtt);

      final hero = tester.getRect(find.byKey(_heroBox));
      final grid = tester.getRect(find.byType(TileGrid));
      final header = tester.getRect(find.byType(DashboardHeader));
      expect(hero.top, header.bottom);
      expect(hero.height, greaterThan(kHeroMinHeight));
      // The tiles rest at the bottom, and the hero ends where their layer
      // starts.
      expect(grid.bottom, closeTo(800 - kDashboardGutter, 0.5));
      expect(hero.bottom, closeTo(grid.top - kDashboardGutter, 0.5));
      await harness.dispose();
    });

    testWidgets('stops at its minimum and the tiles scroll over it', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.pump(type: TransportType.mqtt, textScale: 2, height: 480);

      final hero = tester.getRect(find.byKey(_heroBox));
      expect(hero.height, kHeroMinHeight);
      final gridTop = tester.getRect(find.byType(TileGrid)).top;
      expect(gridTop, closeTo(hero.bottom + kDashboardGutter, 0.5));

      await tester.drag(find.byType(TileGrid), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_heroBox)), hero);
      expect(tester.getRect(find.byType(TileGrid)).top, lessThan(gridTop));
      await harness.dispose();
    });
  });

  testWidgets('dims values that are not live', (tester) async {
    final harness = _Harness(tester);
    await harness.pump();
    final odometer = find.text('Odometer');
    expect(_opacityOf(tester, odometer), kStaleOpacity);

    harness.transport.emit(_liveState());
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, odometer), 1);
    expect(find.text('Bluetooth'), findsOneWidget);

    // The device went quiet: the values stay, dimmed.
    await tester.pump(kStateLivenessTimeout);
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, odometer), kStaleOpacity);
    expect(find.text('Offline · Updated just now'), findsOneWidget);
    await harness.dispose();
  });

  test('says how long ago the state was updated', () {
    final now = DateTime(2026, 11, 7, 12);
    String ago(Duration d) => formatUpdatedAgo(now.subtract(d), now);
    expect(ago(const Duration(seconds: 20)), 'just now');
    expect(ago(const Duration(minutes: 12)), '12 min ago');
    expect(ago(const Duration(hours: 3, minutes: 5)), '3 h ago');
    expect(ago(const Duration(days: 2)), '2 d ago');
  });
}
