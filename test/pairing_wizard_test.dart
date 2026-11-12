import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_car_app/cars/virtual_car/constants.g.dart' as virtual_car;
import 'package:open_car_app/cars/virtual_car/skin.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/main.dart';
import 'package:open_car_app/providers/ble_provider.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/screens/pairing_wizard_screen.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/ble_fragmentation.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _id = 'D4:F9:8D:1F:17:E4';

enum _Link {
  /// Connects, bonds and reports the virtual car's platform.
  pairs,

  /// Never connects.
  silent,

  /// Connects, then drops during the bonding write.
  dropsDuringBonding,
}

/// Scans find one device advertising [name], unless [finds] is false; a
/// connection then behaves as [link] says.
class _FakeBle implements FlutterReactiveBle {
  _FakeBle({
    this.name = 'OpenCar-17E4',
    this.finds = true,
    this.link = _Link.pairs,
  });

  final String name;
  final bool finds;
  _Link link;

  StreamController<ConnectionStateUpdate>? _connection;

  ConnectionStateUpdate _update(DeviceConnectionState state) =>
      ConnectionStateUpdate(
        deviceId: _id,
        connectionState: state,
        failure: null,
      );

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    ScanMode scanMode = ScanMode.balanced,
    bool requireLocationServicesEnabled = true,
  }) => finds
      ? Stream.value(
          DiscoveredDevice(
            id: _id,
            name: name,
            serviceData: const {},
            manufacturerData: Uint8List(0),
            rssi: -50,
            serviceUuids: const [],
          ),
        )
      : const Stream.empty();

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) {
    final connection = StreamController<ConnectionStateUpdate>(
      onListen: () {
        if (link != _Link.silent) {
          _connection!.add(_update(DeviceConnectionState.connected));
        }
      },
      // Without a future of its own, a cancel waits on one from the root zone,
      // which the test's fake clock never runs.
      onCancel: () => Future<void>.value(),
    );
    _connection = connection;
    return connection.stream;
  }

  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) async =>
      mtu;

  @override
  Future<void> discoverAllServices(String deviceId) async {}

  @override
  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) {
    if (link == _Link.dropsDuringBonding) {
      _connection!.add(_update(DeviceConnectionState.disconnected));
      return Completer<void>().future;
    }
    return Future.value();
  }

  @override
  Stream<List<int>> subscribeToCharacteristic(
    QualifiedCharacteristic characteristic,
  ) => Stream.fromIterable(
    splitIntoBleChunks(
      DeviceToApp(platformId: virtual_car.kPlatformId).writeToBuffer(),
      247,
      0,
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTransport implements CarTransport {
  final _controller = StreamController<DeviceToApp>.broadcast();
  final sent = <AppToDevice>[];

  void emit(DeviceToApp message) => _controller.add(message);

  void reportAccess({CanAccessState? can, PhoneAccessState? phone}) => emit(
    DeviceToApp(
      platformId: virtual_car.kPlatformId,
      stateUpdate: StateUpdate(
        systemState: SystemState(canAccess: can, phoneAccess: phone),
      ),
    ),
  );

  @override
  TransportType get transportType => TransportType.ble;

  @override
  Stream<DeviceToApp> get messages => _controller.stream;

  @override
  Future<void> send(AppToDevice message) async => sent.add(message);

  @override
  void dispose() => _controller.close();
}

CanAccessState _access(
  CanReadWriteApproval approval, {
  bool identified = true,
}) => CanAccessState(
  platformConfirmed: true,
  carIdentityConfirmed: identified,
  approval: approval,
  readOnly: true,
);

final _needsApproval = _access(
  CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_NOT_APPROVED,
);

/// Grants every permission `permission_handler` is asked for.
void _grantPermissions() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async => call.method == 'requestPermissions'
            ? {for (final p in call.arguments as List) p as int: 1}
            : 1,
      );
}

/// Lets the futures of a step finish. The rings repeat for ever, so a test
/// can't settle.
Future<void> _advance(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump();
  }
}

Future<void> _startApp(
  WidgetTester tester,
  FlutterReactiveBle ble,
  _FakeTransport transport,
) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  addTearDown(transport.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bleProvider.overrideWithValue(ble),
        bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
        carTransportProvider.overrideWithValue(transport),
      ],
      child: const OpenCarApp(),
    ),
  );
}

Future<void> _scan(
  WidgetTester tester,
  FlutterReactiveBle ble,
  _FakeTransport transport,
) async {
  await _startApp(tester, ble, transport);
  await tester.tap(find.text('Start'));
  await _advance(tester);
}

Future<void> _pair(
  WidgetTester tester,
  FlutterReactiveBle ble,
  _FakeTransport transport,
) async {
  await _scan(tester, ble, transport);
  await tester.tap(find.text('Pair'));
  await _advance(tester);
}

Future<void> _pairAndReachApproval(
  WidgetTester tester,
  _FakeTransport transport,
) async {
  await _pair(tester, _FakeBle(), transport);
  transport.reportAccess(can: _needsApproval);
  await _advance(tester);
}

FilledButton _button(WidgetTester tester, String label) => tester.widget(
  find.ancestor(of: find.text(label), matching: find.byType(FilledButton)),
);

AppTokens _tokensOn(WidgetTester tester, Finder finder) =>
    tester.element(finder).tokens;

Finder get _dashboard => find.byTooltip('Settings');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _grantPermissions();
  });

  group('finding the device', () {
    testWidgets('the prompt is step 1 and uses the default skin', (
      tester,
    ) async {
      await _startApp(tester, _FakeBle(), _FakeTransport());

      expect(find.text('Pair your vehicle'), findsOneWidget);
      expect(find.text('Step 1 of 3 · Find your vehicle'), findsOneWidget);
      expect(find.text('Put your device in pairing mode'), findsOneWidget);
      expect(find.byTooltip('Close'), findsNothing);
      expect(
        _tokensOn(tester, find.text('Start')).accent,
        defaultSkin.accentsFor(Brightness.light).accent,
      );
    });

    testWidgets('scanning shows the time left and can be cancelled', (
      tester,
    ) async {
      await _scan(tester, _FakeBle(finds: false), _FakeTransport());

      expect(find.text('Looking for your vehicle…'), findsOneWidget);
      expect(
        find.text('${virtual_car.kBleScanTimeoutSeconds} s remaining'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await _advance(tester);
      expect(find.text('Put your device in pairing mode'), findsOneWidget);
    });

    testWidgets('a scan that finds nothing times out, and can be retried', (
      tester,
    ) async {
      await _scan(tester, _FakeBle(finds: false), _FakeTransport());

      await tester.pump(
        const Duration(seconds: virtual_car.kBleScanTimeoutSeconds + 1),
      );
      await _advance(tester);

      expect(find.text('No vehicle found'), findsOneWidget);
      expect(find.text('Step 1 of 3 · Find your vehicle'), findsOneWidget);
      expect(find.textContaining('see Help to reset'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await _advance(tester);
      expect(find.text('Put your device in pairing mode'), findsOneWidget);
    });
  });

  group('the found step', () {
    testWidgets('a device found without its name is outside pairing mode', (
      tester,
    ) async {
      // Android reports a device it cached while paired, even though the
      // device advertises neither its name nor its service outside pairing
      // mode.
      await _scan(tester, _FakeBle(name: ''), _FakeTransport());

      expect(find.text('Vehicle found'), findsOneWidget);
      expect(find.text('Step 2 of 3 · Pair'), findsOneWidget);
      expect(find.text(_id), findsOneWidget);
      expect(find.textContaining('not in pairing mode'), findsOneWidget);
      // The one in the header, and the one under the note.
      expect(find.text('Help'), findsNWidgets(2));
      expect(find.text('Pair'), findsOneWidget);
    });

    testWidgets('a device found with its name is in pairing mode', (
      tester,
    ) async {
      await _scan(tester, _FakeBle(), _FakeTransport());

      expect(find.text('OpenCar-17E4'), findsOneWidget);
      expect(find.textContaining('not in pairing mode'), findsNothing);
      expect(find.text('Help'), findsOneWidget);
    });
  });

  group('pairing', () {
    testWidgets('waits for the phone\'s pairing request', (tester) async {
      await _pair(tester, _FakeBle(link: _Link.silent), _FakeTransport());

      expect(find.text('Pairing…'), findsOneWidget);
      expect(find.text('Step 2 of 3 · Pair'), findsOneWidget);

      await tester.pump(
        const Duration(seconds: virtual_car.kBlePairingWindowSeconds + 1),
      );
      await _advance(tester);
    });

    testWidgets(
      'times out when the device never connects, and can be retried',
      (tester) async {
        await _pair(tester, _FakeBle(link: _Link.silent), _FakeTransport());

        await tester.pump(
          const Duration(seconds: virtual_car.kBlePairingWindowSeconds + 1),
        );
        await _advance(tester);

        expect(find.text('Pairing timed out'), findsOneWidget);
        expect(find.text('Step 2 of 3 · Pair'), findsOneWidget);
        expect(
          find.textContaining('pairing window is still open'),
          findsOneWidget,
        );
        expect(find.text('Help'), findsNWidgets(2));

        await tester.tap(find.text('Try again'));
        await _advance(tester);
        expect(find.text('Put your device in pairing mode'), findsOneWidget);
      },
    );

    testWidgets('a link dropped while bonding is a stale bond', (tester) async {
      final ble = _FakeBle(link: _Link.dropsDuringBonding);
      await _pair(tester, ble, _FakeTransport());

      expect(find.text('Vehicle found'), findsOneWidget);
      expect(find.textContaining('The old pairing is cleared'), findsOneWidget);

      // The device cleared its entry, so the next attempt pairs.
      ble.link = _Link.pairs;
      await tester.tap(find.text('Pair'));
      await _advance(tester);
      expect(find.text('Connecting to your vehicle…'), findsOneWidget);
    });

    testWidgets('a stale bond outside pairing mode points to the reset', (
      tester,
    ) async {
      await _pair(
        tester,
        _FakeBle(name: '', link: _Link.dropsDuringBonding),
        _FakeTransport(),
      );

      expect(find.textContaining('Reset its paired phones'), findsOneWidget);
    });
  });

  group('setting up', () {
    testWidgets('pairing stays in the wizard, in the vehicle\'s skin', (
      tester,
    ) async {
      await _pair(tester, _FakeBle(), _FakeTransport());
      // The first frame starts the theme's animation, the next ends it.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Connecting to your vehicle…'), findsOneWidget);
      expect(find.text('Step 3 of 3 · Set up'), findsOneWidget);
      expect(_dashboard, findsNothing);
      expect(
        _tokensOn(tester, find.text('Not now')).accent,
        virtualCarSkin.accentsFor(Brightness.light).accent,
      );

      // Closes the set-up, so its timer doesn't outlive the test.
      await tester.tap(find.text('Not now'));
      await _advance(tester);
    });

    testWidgets('allowing control needs the acknowledgement', (tester) async {
      final transport = _FakeTransport();
      await _pairAndReachApproval(tester, transport);

      expect(find.text('Allow control of this car?'), findsOneWidget);
      expect(find.textContaining('experimental software'), findsOneWidget);
      expect(_button(tester, 'Allow control').onPressed, isNull);

      await tester.ensureVisible(find.text('I understand the risks'));
      await tester.tap(find.text('I understand the risks'));
      await _advance(tester);
      await tester.tap(find.text('Allow control'));
      await _advance(tester);

      final sent = transport.sent.single;
      expect(sent.systemCommand.setCanReadWriteApproval.approved, isTrue);
      expect(_dashboard, findsNothing);

      transport.emit(
        DeviceToApp(
          commandResponse: CommandResponse(
            messageId: sent.messageId,
            success: true,
          ),
        ),
      );
      await _advance(tester);
      expect(_dashboard, findsOneWidget);
    });

    testWidgets(
      'the device refusing the approval is shown, and can be skipped',
      (tester) async {
        final transport = _FakeTransport();
        await _pairAndReachApproval(tester, transport);

        await tester.ensureVisible(find.text('I understand the risks'));
        await tester.tap(find.text('I understand the risks'));
        await _advance(tester);
        await tester.tap(find.text('Allow control'));
        await _advance(tester);
        transport.emit(
          DeviceToApp(
            commandResponse: CommandResponse(
              messageId: transport.sent.single.messageId,
              success: false,
              errorMessage: 'the car is not identified',
            ),
          ),
        );
        await _advance(tester);

        expect(
          find.textContaining('the car is not identified'),
          findsOneWidget,
        );
        expect(_dashboard, findsNothing);

        await tester.tap(find.text('Not now'));
        await _advance(tester);
        expect(_dashboard, findsOneWidget);
      },
    );

    testWidgets('Not now skips the approval', (tester) async {
      final transport = _FakeTransport();
      await _pairAndReachApproval(tester, transport);

      await tester.tap(find.text('Not now'));
      await _advance(tester);

      expect(_dashboard, findsOneWidget);
      expect(transport.sent, isEmpty);
    });

    testWidgets('a car already approved skips the step', (tester) async {
      final transport = _FakeTransport();
      await _pair(tester, _FakeBle(), transport);

      transport.reportAccess(
        can: _access(CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_APPROVED),
      );
      await _advance(tester);

      expect(_dashboard, findsOneWidget);
    });

    testWidgets('a phone the device would refuse skips the step', (
      tester,
    ) async {
      final transport = _FakeTransport();
      await _pair(tester, _FakeBle(), transport);

      transport.reportAccess(
        can: _needsApproval,
        phone: PhoneAccessState(
          trust: PhoneTrustLevel.PHONE_TRUST_LEVEL_BONDED,
          carHasValidatedPhone: true,
        ),
      );
      await _advance(tester);

      expect(find.text('Allow control of this car?'), findsNothing);
      expect(_dashboard, findsOneWidget);
    });

    testWidgets('a device that reports nothing ends on the dashboard', (
      tester,
    ) async {
      await _pair(tester, _FakeBle(), _FakeTransport());

      await tester.pump(const Duration(seconds: 21));
      await _advance(tester);

      expect(_dashboard, findsOneWidget);
    });

    testWidgets('a car not identified yet waits, then ends on the dashboard', (
      tester,
    ) async {
      final transport = _FakeTransport();
      await _pair(tester, _FakeBle(), transport);

      transport.reportAccess(
        can: _access(
          CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_NOT_APPROVED,
          identified: false,
        ),
      );
      await _advance(tester);
      expect(find.text('Connecting to your vehicle…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 21));
      await _advance(tester);
      expect(_dashboard, findsOneWidget);
    });
  });

  group('adding a vehicle', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildAppTheme(virtualCarSkin, Brightness.light),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PairingWizardScreen(addVehicle: true),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('has its heading and a close button', (tester) async {
      await open(tester);

      expect(find.text('Add a vehicle'), findsOneWidget);
      expect(find.text('Pair your vehicle'), findsNothing);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('uses the default skin until the vehicle is known', (
      tester,
    ) async {
      await open(tester);

      expect(
        _tokensOn(tester, find.text('Start')).accent,
        defaultSkin.accentsFor(Brightness.light).accent,
      );
    });
  });

  testWidgets('the HTTP debug form is reachable in the frame', (tester) async {
    await _startApp(tester, _FakeBle(), _FakeTransport());

    await tester.tap(find.text('Use HTTP instead (debug)'));
    await _advance(tester);

    expect(find.text('HTTP Debug Transport'), findsOneWidget);
    expect(find.text('Step 1 of 3 · Find your vehicle'), findsOneWidget);
    expect(_button(tester, 'Pair').onPressed, isNull);

    await tester.tap(find.text('Back to BLE'));
    await _advance(tester);
    expect(find.text('Put your device in pairing mode'), findsOneWidget);
  });
}
