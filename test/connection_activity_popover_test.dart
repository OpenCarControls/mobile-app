import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/virtual_car/virtual_car_definition.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/models/connection_activity.dart';
import 'package:open_car_app/providers/ble_connection_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/connection_activity_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/screens/dashboard/connection_activity_popover.dart';
import 'package:open_car_app/screens/dashboard/dashboard_header.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';

const _remoteId = 'AA:BB:CC:DD:EE:FF';

const _config = PairedVehicleConfig(
  vehicleId: 'virtual',
  bleRemoteId: _remoteId,
  transportPreference: TransportPreference.ble,
);

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

class _FakeBle extends BleConnectionNotifier {
  _FakeBle({this.link = const BleDisconnected()});

  final BleConnectionState link;
  int refreshes = 0;

  @override
  BleConnectionState build() => link;

  @override
  Future<void> pullToRefresh() async => refreshes++;
}

VehicleSnapshot _snapshot({required bool live, DateTime? updated}) =>
    VehicleSnapshot(
      basicState: BasicState(),
      advancedState: AdvancedState(),
      isStateLive: live,
      lastUpdated: updated,
    );

class _FakeState extends VehicleStateNotifier {
  _FakeState(this.snapshot);

  final VehicleSnapshot snapshot;

  @override
  VehicleSnapshot build() => snapshot;
}

void main() {
  late List<String> shared;
  late _FakeBle ble;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Open Car',
      packageName: 'test',
      version: '1.2.3',
      buildNumber: '1',
      buildSignature: '',
    );
    shared = [];
    ble = _FakeBle();
  });

  Future<void> open(
    WidgetTester tester, {
    required List<ConnectionActivityEntry> entries,
    required VehicleSnapshot snapshot,
    TransportType link = TransportType.ble,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialPairedVehiclesProvider.overrideWithValue(
            PairedVehicles.of(_config),
          ),
          initialConnectionActivityProvider.overrideWithValue({
            _config.storageKey: entries,
          }),
          selectedVehicleProvider.overrideWithValue(
            const VirtualCarDefinition(),
          ),
          carTransportProvider.overrideWithValue(_Transport(link)),
          vehicleStateProvider.overrideWith(() => _FakeState(snapshot)),
          bleConnectionProvider.overrideWith(() => ble),
          shareTextProvider.overrideWithValue((text) async => shared.add(text)),
        ],
        child: MaterialApp(
          theme: buildAppTheme(defaultSkin, Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                height: 44,
                child: ConnectionPill(snapshot: snapshot),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ConnectionPill));
    await tester.pumpAndSettle();
  }

  /// Closes the popover and its timer.
  Future<void> finish(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('shows the state, the actions and the log', (tester) async {
    final now = DateTime.now();
    await open(
      tester,
      snapshot: _snapshot(live: true, updated: now),
      entries: [
        ConnectionChangeEntry(
          now.subtract(const Duration(minutes: 12, seconds: 5)),
          ConnectionChange.bluetoothConnected,
        ),
        CommandEntry(
          now.subtract(const Duration(minutes: 20)),
          command: 'Lock doors',
          outcome: CommandOutcome.done,
          sentRemotely: true,
        ),
      ],
    );

    expect(find.text('Connected over Bluetooth'), findsOneWidget);
    expect(find.text('For 12 min · last update just now'), findsOneWidget);
    expect(find.text('Reconnect Bluetooth'), findsOneWidget);
    expect(find.text('Share log'), findsOneWidget);
    expect(find.text('Bluetooth connected'), findsOneWidget);
    expect(find.text('Lock doors'), findsOneWidget);
    expect(find.text('Done · sent remotely'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('offline shows only the last update', (tester) async {
    final now = DateTime.now();
    await open(
      tester,
      link: TransportType.mqtt,
      snapshot: _snapshot(
        live: false,
        updated: now.subtract(const Duration(minutes: 3)),
      ),
      entries: [
        ConnectionChangeEntry(
          now.subtract(const Duration(hours: 1)),
          ConnectionChange.remoteConnected,
        ),
      ],
    );

    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Last update 3 min ago'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a failure uses the danger colour on its detail only', (
    tester,
  ) async {
    await open(
      tester,
      snapshot: _snapshot(live: true),
      entries: [
        CommandEntry(
          DateTime.now(),
          command: 'Climate on',
          outcome: CommandOutcome.noAnswer,
        ),
      ],
    );

    final danger = tester.element(find.text('Climate on')).tokens.danger;
    expect(
      tester.widget<Text>(find.text('No answer from the vehicle')).style?.color,
      danger,
    );
    expect(
      tester.widget<Text>(find.text('Climate on')).style?.color,
      isNot(danger),
    );
    await finish(tester);
  });

  testWidgets('Reconnect Bluetooth is the pull-to-refresh action', (
    tester,
  ) async {
    await open(tester, snapshot: _snapshot(live: false), entries: const []);

    await tester.tap(find.text('Reconnect Bluetooth'));
    await tester.pump();

    expect(ble.refreshes, 1);
    await finish(tester);
  });

  testWidgets('Reconnect Bluetooth is off while connected', (tester) async {
    ble = _FakeBle(link: const BleReady(_remoteId, attMtu: 247));
    await open(tester, snapshot: _snapshot(live: true), entries: const []);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Reconnect Bluetooth'),
    );
    expect(button.onPressed, isNull);
    await finish(tester);
  });

  testWidgets('Share log shares the plain text', (tester) async {
    await open(
      tester,
      snapshot: _snapshot(live: true),
      entries: [
        CommandEntry(
          DateTime(2026, 11, 9, 14, 21),
          command: 'Unlock doors',
          outcome: CommandOutcome.done,
        ),
      ],
    );

    await tester.tap(find.text('Share log'));
    await tester.pumpAndSettle();

    expect(shared.single, contains('App version: 1.2.3'));
    expect(shared.single, contains('2026-11-09 14:21  Unlock doors · Done'));
    expect(shared.single, isNot(contains(_remoteId)));
    await finish(tester);
  });

  testWidgets('Share log is off with nothing to share', (tester) async {
    await open(tester, snapshot: _snapshot(live: false), entries: const []);

    expect(find.text('Nothing to show yet.'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Share log'),
    );
    expect(button.onPressed, isNull);
    await finish(tester);
  });

  testWidgets('the close button and tapping outside close it', (tester) async {
    await open(tester, snapshot: _snapshot(live: false), entries: const []);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Connection'), findsNothing);

    await tester.tap(find.byType(ConnectionPill));
    await tester.pumpAndSettle();
    expect(find.text('Connection'), findsOneWidget);

    await tester.tapAt(const Offset(200, 790));
    await tester.pumpAndSettle();
    expect(find.text('Connection'), findsNothing);
  });

  testWidgets('follows the pill when the layout moves it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final top = ValueNotifier<double>(20);
    addTearDown(top.dispose);
    final snapshot = _snapshot(live: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialPairedVehiclesProvider.overrideWithValue(
            PairedVehicles.of(_config),
          ),
          selectedVehicleProvider.overrideWithValue(
            const VirtualCarDefinition(),
          ),
          carTransportProvider.overrideWithValue(
            const _Transport(TransportType.ble),
          ),
          vehicleStateProvider.overrideWith(() => _FakeState(snapshot)),
          bleConnectionProvider.overrideWith(() => ble),
        ],
        child: MaterialApp(
          theme: buildAppTheme(defaultSkin, Brightness.light),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: top,
              builder: (_, value, _) => Padding(
                padding: EdgeInsets.only(top: value),
                child: Align(
                  alignment: Alignment.topRight,
                  child: SizedBox(
                    height: 44,
                    // A new pill, as when the dashboard switches layout.
                    child: ConnectionPill(
                      key: ValueKey(value),
                      snapshot: snapshot,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ConnectionPill));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('Connection')).dy;

    top.value = 78;
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Connection')).dy, before + 58);
    await finish(tester);
  });

  group('connectedSince', () {
    final time = DateTime(2026, 11, 9, 12);

    test('is the newest connection', () {
      expect(
        connectedSince([
          CommandEntry(
            time.add(const Duration(hours: 1)),
            command: 'Lock',
            outcome: CommandOutcome.done,
          ),
          ConnectionChangeEntry(time, ConnectionChange.remoteConnected),
          ConnectionChangeEntry(
            time.subtract(const Duration(hours: 1)),
            ConnectionChange.bluetoothLost,
          ),
        ]),
        time,
      );
    });

    test('is null after losing the link or with no connection', () {
      expect(
        connectedSince([
          ConnectionChangeEntry(time, ConnectionChange.bluetoothLost),
          ConnectionChangeEntry(
            time.subtract(const Duration(hours: 1)),
            ConnectionChange.bluetoothConnected,
          ),
        ]),
        isNull,
      );
      expect(connectedSince(const []), isNull);
    });
  });

  group('day heading', () {
    const localizations = DefaultMaterialLocalizations();
    final now = DateTime(2026, 11, 9, 0, 30);

    String heading(DateTime day) =>
        connectionActivityDayHeading(day, now, localizations);

    test('names today and yesterday', () {
      expect(heading(DateTime(2026, 11, 9, 23, 59)), 'TODAY');
      expect(heading(DateTime(2026, 11, 8, 23, 59)), 'YESTERDAY');
    });

    test('dates anything older', () {
      expect(heading(DateTime(2026, 11, 3, 12)), 'TUE, NOV 3');
    });
  });
}
