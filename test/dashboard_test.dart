import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/virtual_car/command_ids.dart';
import 'package:open_car_app/cars/virtual_car/constants.g.dart' as virtual_car;
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/phone_access_provider.dart';
import 'package:open_car_app/screens/phone_validation_screen.dart';
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
import 'package:open_car_app/widgets/tiles/catalog_tile.dart';
import 'package:open_car_app/widgets/tiles/tile_editing.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

class _FakeTransport implements CarTransport {
  _FakeTransport(this.transportType);

  final _controller = StreamController<DeviceToApp>.broadcast();
  final sent = <AppToDevice>[];

  void emit(DeviceToApp msg) => _controller.add(msg);

  @override
  final TransportType transportType;

  @override
  Stream<DeviceToApp> get messages => _controller.stream;

  @override
  Future<void> send(AppToDevice message) async => sent.add(message);

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

class _AccessNotifier extends PhoneAccessStateNotifier {
  _AccessNotifier(this._initial);

  final PhoneTrustLevel? _initial;

  @override
  PhoneAccessState? build() =>
      _initial == null ? null : PhoneAccessState(trust: _initial);

  void report(PhoneTrustLevel trust) => state = PhoneAccessState(trust: trust);
}

const _heroBox = Key('dashboard-hero-box');
const _validated = PhoneTrustLevel.PHONE_TRUST_LEVEL_VALIDATED;
const _bonded = PhoneTrustLevel.PHONE_TRUST_LEVEL_BONDED;

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
  late final _AccessNotifier _access;

  _FakeTransport get transport =>
      transports[_type.state] ?? transports[TransportType.ble]!;

  Future<void> pump({
    TransportType type = TransportType.ble,
    double textScale = 1,
    double height = 800,
    PhoneTrustLevel? trust = _validated,
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
    _access = _AccessNotifier(trust);
    final typeProvider = NotifierProvider<_TypeNotifier, TransportType>(
      () => _type,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
          initialPairedVehiclesProvider.overrideWithValue(
            PairedVehicles.of(_config),
          ),
          carTransportProvider.overrideWith(
            (ref) => transports[ref.watch(typeProvider)]!,
          ),
          phoneAccessStateProvider.overrideWith(() => _access),
        ],
        child: MaterialApp(
          theme: buildAppTheme(defaultSkin, Brightness.light),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// What the device reports about this phone. Set directly: a report over the
  /// transport would also make the state live.
  void reportTrust(PhoneTrustLevel trust) => _access.report(trust);

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

  group('a phone that is not validated', () {
    testWidgets('sees the remote layout until the device says it is', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.pump(trust: null);
      expect(find.byKey(_heroBox), findsOneWidget, reason: 'unknown');

      harness.reportTrust(_bonded);
      await tester.pumpAndSettle();
      expect(find.byKey(_heroBox), findsOneWidget, reason: 'bonded');
      expect(find.text('Custom 1'), findsNothing);
      harness.transport.emit(_liveState());
      await tester.pumpAndSettle();
      expect(find.text('Bluetooth'), findsOneWidget, reason: 'the real link');

      harness.reportTrust(_validated);
      await tester.pumpAndSettle();
      expect(find.byKey(_heroBox), findsNothing);
      expect(find.text('Custom 1'), findsOneWidget);
      await harness.dispose();
    });

    testWidgets('is offered the validation by the banner', (tester) async {
      final harness = _Harness(tester);
      await harness.pump(trust: _bonded);
      await tester.tap(find.text('Validate'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PhoneValidationScreen), findsOneWidget);
      await harness.dispose();
      await tester.pump(const Duration(seconds: 16));
    });

    testWidgets('opens the validation from a greyed-out tile', (tester) async {
      final harness = _Harness(tester);
      await harness.pump(trust: _bonded);
      await tester.tap(find.bySemanticsLabel(RegExp('^Doors, ')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PhoneValidationScreen), findsOneWidget);
      await harness.dispose();
      await tester.pump(const Duration(seconds: 16));
    });

    testWidgets('a validated phone gets no banner', (tester) async {
      final harness = _Harness(tester);
      await harness.pump();
      expect(find.text('Validate this phone'), findsNothing);
      await harness.dispose();
    });
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

  group('editing the layout', () {
    Finder editing(String label) => find.byWidgetPredicate(
      (w) => w is EditingTile && w.tile.label == label,
    );
    Finder tooltip(String message) => find.byTooltip(message);
    Finder remove(String label) =>
        find.descendant(of: editing(label), matching: find.byIcon(Icons.close));

    /// The order of the tiles, as the editor shows them.
    List<String> order(WidgetTester tester) => [
      for (final tile in tester.widgetList<EditingTile>(
        find.byType(EditingTile),
      ))
        tile.tile.label,
    ];

    Future<_Harness> startEditing(WidgetTester tester) async {
      final harness = _Harness(tester);
      await harness.pump();
      await tester.tap(tooltip('Edit layout'));
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('Add, Done and Reset share a row', (tester) async {
      final harness = await startEditing(tester);
      expect(tooltip('Edit layout'), findsNothing);
      final tops = {
        for (final name in ['Add a tile', 'Done', 'Reset layout'])
          tester.getTopLeft(tooltip(name)).dy,
      };
      expect(tops, hasLength(1));
      await tester.tap(tooltip('Done'));
      await tester.pumpAndSettle();
      expect(tooltip('Edit layout'), findsOneWidget);
      expect(find.byType(EditingTile), findsNothing);
      await harness.dispose();
    });

    testWidgets('commands do not run while editing', (tester) async {
      final harness = await startEditing(tester);
      await tester.tap(editing('Doors'));
      await tester.pumpAndSettle();
      expect(harness.transport.sent, isEmpty);
      await harness.dispose();
    });

    testWidgets('holding a tile starts editing and sends nothing', (
      tester,
    ) async {
      final harness = _Harness(tester);
      await harness.pump();
      await tester.longPress(find.text('Custom 1'));
      await tester.pumpAndSettle();
      expect(find.byType(EditingTile), findsWidgets);
      expect(harness.transport.sent, isEmpty);
      await harness.dispose();
    });

    testWidgets('the remote grid can not be edited', (tester) async {
      final harness = _Harness(tester);
      await harness.pump(type: TransportType.mqtt);
      expect(tooltip('Edit layout'), findsNothing);
      await tester.longPress(find.byType(CatalogTile).first);
      await tester.pumpAndSettle();
      expect(find.byType(EditingTile), findsNothing);
      await harness.dispose();
    });

    testWidgets('a tile can be removed, added back and resized', (
      tester,
    ) async {
      final harness = await startEditing(tester);
      await tester.tap(remove('Doors'));
      await tester.pumpAndSettle();
      expect(editing('Doors'), findsNothing);

      await tester.tap(tooltip('Add a tile'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Doors'));
      await tester.pumpAndSettle();
      expect(order(tester).last, 'Doors');

      expect(
        find.descendant(of: editing('Doors'), matching: find.text('1×1')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: editing('Doors'), matching: find.text('1×1')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: editing('Doors'), matching: find.text('2×1')),
        findsOneWidget,
      );
      await harness.dispose();
    });

    testWidgets('a tile the car lacks is greyed out in the add list', (
      tester,
    ) async {
      final harness = await startEditing(tester);
      harness.transport.emit(
        DeviceToApp(
          platformId: virtual_car.kPlatformId,
          stateUpdate: StateUpdate(
            systemState: SystemState(
              commandAvailability: CommandAvailability(
                basic: {
                  kDoorLockCommand.id: CommandAvailabilityState
                      .COMMAND_AVAILABILITY_STATE_UNSUPPORTED,
                }.entries,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(editing('Doors'), findsNothing);

      await tester.tap(tooltip('Add a tile'));
      await tester.pumpAndSettle();
      final doors = find.widgetWithText(ListTile, 'Doors');
      expect(tester.widget<ListTile>(doors).enabled, isFalse);
      await tester.tap(doors);
      await tester.pumpAndSettle();
      expect(editing('Doors'), findsNothing);
      await harness.dispose();
    });

    testWidgets('the move actions work without dragging', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = await startEditing(tester);
      final before = order(tester);

      void perform(String label, CustomSemanticsAction action) {
        final node = tester.getSemantics(editing(label));
        node.owner!.performAction(
          node.id,
          SemanticsAction.customAction,
          CustomSemanticsAction.getIdentifier(action),
        );
      }

      perform(before[1], EditingTile.moveEarlierAction);
      await tester.pumpAndSettle();
      expect(order(tester), [before[1], before[0], ...before.skip(2)]);

      perform(before[1], EditingTile.moveLaterAction);
      await tester.pumpAndSettle();
      expect(order(tester), before);

      expect(
        tester.widget<EditingTile>(editing(before.first)).onMoveEarlier,
        isNull,
      );
      expect(
        tester.widget<EditingTile>(editing(before.last)).onMoveLater,
        isNull,
      );
      await harness.dispose();
      semantics.dispose();
    });

    testWidgets('reset asks first, then restores and leaves edit mode', (
      tester,
    ) async {
      final harness = await startEditing(tester);
      final before = order(tester);
      await tester.tap(remove('Doors'));
      await tester.pumpAndSettle();
      final edited = order(tester);

      await tester.tap(tooltip('Reset layout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(order(tester), edited);

      await tester.tap(tooltip('Reset layout'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Reset'));
      await tester.pumpAndSettle();
      expect(find.byType(EditingTile), findsNothing);

      await tester.tap(tooltip('Edit layout'));
      await tester.pumpAndSettle();
      expect(order(tester), before);
      await harness.dispose();
    });

    testWidgets('pull-to-refresh is off only while editing', (tester) async {
      final harness = _Harness(tester);
      await harness.pump();

      Future<bool> refreshShows() async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(TileGrid)),
        );
        // Far enough to show the indicator, not to arm a real refresh.
        for (var i = 0; i < 4; i++) {
          await gesture.moveBy(const Offset(0, 20));
          await tester.pump(const Duration(milliseconds: 16));
        }
        final shown = find
            .byType(RefreshProgressIndicator)
            .evaluate()
            .isNotEmpty;
        await gesture.cancel();
        await tester.pumpAndSettle();
        return shown;
      }

      expect(await refreshShows(), isTrue);
      await tester.tap(tooltip('Edit layout'));
      await tester.pumpAndSettle();
      expect(await refreshShows(), isFalse);
      await harness.dispose();
    });

    /// Holds [label]'s tile, then drags it [delta] with the finger still down.
    Future<TestGesture> holdAndDrag(
      WidgetTester tester,
      Finder tile,
      Offset delta,
    ) async {
      final gesture = await tester.startGesture(tester.getCenter(tile));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      await gesture.moveBy(delta);
      await tester.pumpAndSettle();
      return gesture;
    }

    testWidgets('dragging a tile moves it and keeps it', (tester) async {
      final harness = await startEditing(tester);
      final before = order(tester);
      final start = tester.getTopLeft(editing(before[0]));
      final next = tester.getTopLeft(editing(before[1]));

      final gesture = await holdAndDrag(
        tester,
        editing(before[0]),
        next - start,
      );
      // It stays under the finger while the others slide.
      expect(tester.getTopLeft(editing(before[0])), next);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(order(tester), [before[1], before[0], ...before.skip(2)]);
      expect(tester.getTopLeft(editing(before[0])), next);
      expect(tester.getTopLeft(editing(before[1])), start);
      await harness.dispose();
    });

    testWidgets('the same hold starts editing and drags', (tester) async {
      final harness = _Harness(tester);
      await harness.pump();
      final finder = find.text('Custom 1');
      final gesture = await holdAndDrag(tester, finder, const Offset(-100, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(order(tester).first, 'Custom 1');
      expect(harness.transport.sent, isEmpty);
      await harness.dispose();
    });

    testWidgets('the edit controls stay last', (tester) async {
      final harness = await startEditing(tester);
      final before = order(tester);
      final gesture = await holdAndDrag(
        tester,
        editing(before.first),
        const Offset(300, 400),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      final draggable = [
        for (final item in tester.widget<TileGrid>(find.byType(TileGrid)).items)
          item.drag != null,
      ];
      expect(draggable, [...before.map((_) => true), false, false]);
      await harness.dispose();
    });

    testWidgets('edit mode explains the gestures', (tester) async {
      final harness = await startEditing(tester);
      expect(find.textContaining('Hold a tile'), findsOneWidget);
      await harness.dispose();
    });

    testWidgets('a link change ends editing', (tester) async {
      final harness = await startEditing(tester);
      await harness.switchTo(TransportType.mqtt);
      await harness.switchTo(TransportType.ble);
      expect(find.byType(EditingTile), findsNothing);
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
