import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/egmp/constants.g.dart' as egmp;
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/providers/ble_connection_provider.dart';
import 'package:open_car_app/providers/ble_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';

const _remoteId = '00:11:22:33:44:55';

/// A BLE stack whose link comes up instantly. By default it never exposes the
/// car's service, so post-connect setup always fails ([mtuFails] makes it fail
/// earlier, [mtu] sets what the MTU request returns). With [hasCarService] the
/// setup succeeds. [mtuGate] holds the MTU request until the test completes
/// it, so the test can drop the link mid-setup with [dropLink]. With
/// [refuseAfter] the link never comes up: the attempt goes `connecting`, then
/// `disconnected` after that long. Each call to [connectToDevice] counts as one
/// attempt and cancelling its stream counts as a disconnect.
class _FakeBle implements FlutterReactiveBle {
  _FakeBle({
    this.mtuFails = false,
    this.mtu = egmp.kBleAttMtu,
    this.hasCarService = false,
    this.mtuGate,
    this.refuseAfter,
  });

  final bool mtuFails;
  final int mtu;
  final bool hasCarService;
  final Completer<void>? mtuGate;
  final Duration? refuseAfter;
  int connectCalls = 0;
  int disconnects = 0;
  int discoverCalls = 0;
  StreamController<ConnectionStateUpdate>? _link;

  /// The device hangs up: `disconnected`, then the stream ends.
  void dropLink() {
    final link = _link!;
    link.add(
      const ConnectionStateUpdate(
        deviceId: _remoteId,
        connectionState: DeviceConnectionState.disconnected,
        failure: null,
      ),
    );
    unawaited(link.close());
  }

  @override
  Stream<BleStatus> get statusStream => Stream.value(BleStatus.ready);

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) {
    connectCalls++;
    late final StreamController<ConnectionStateUpdate> controller;
    void emit(DeviceConnectionState connectionState) => controller.add(
      ConnectionStateUpdate(
        deviceId: id,
        connectionState: connectionState,
        failure: null,
      ),
    );
    Timer? refusal;
    controller = StreamController<ConnectionStateUpdate>(
      onListen: () {
        final refuseAfter = this.refuseAfter;
        if (refuseAfter == null) {
          emit(DeviceConnectionState.connected);
          return;
        }
        emit(DeviceConnectionState.connecting);
        refusal = Timer(refuseAfter, () {
          emit(DeviceConnectionState.disconnected);
          unawaited(controller.close());
        });
      },
      onCancel: () {
        refusal?.cancel();
        disconnects++;
      },
    );
    _link = controller;
    return controller.stream;
  }

  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) async {
    await mtuGate?.future;
    if (mtuFails) throw Exception('MTU request failed');
    return this.mtu;
  }

  @override
  Future<void> clearGattCache(String deviceId) async {}

  @override
  Future<void> discoverAllServices(String deviceId) async => discoverCalls++;

  @override
  Future<List<Service>> getDiscoveredServices(
    String deviceId, {
    Duration timeout = const Duration(seconds: 10),
  }) async => hasCarService
      ? [
          _FakeService(Uuid.parse(egmp.kBleServiceUuid), [
            Uuid.parse(egmp.kBleAppToDeviceCharacteristicUuid),
            Uuid.parse(egmp.kBleDeviceToAppCharacteristicUuid),
          ]),
        ]
      : const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [Service] and [Characteristic] have private constructors; the provider
/// only reads their ids.
class _FakeService implements Service {
  _FakeService(this.id, List<Uuid> characteristicIds)
    : characteristics = [
        for (final id in characteristicIds) _FakeCharacteristic(id),
      ];

  @override
  final Uuid id;
  @override
  final List<Characteristic> characteristics;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCharacteristic implements Characteristic {
  _FakeCharacteristic(this.id);

  @override
  final Uuid id;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(
  _FakeBle ble, {
  TransportPreference preference = TransportPreference.ble,
}) {
  final container = ProviderContainer(
    overrides: [
      bleProvider.overrideWithValue(ble),
      initialPairedVehicleConfigProvider.overrideWithValue(
        PairedVehicleConfig(
          vehicleId: egmp.kPlatformName,
          bleRemoteId: _remoteId,
          transportPreference: preference,
        ),
      ),
    ],
  );
  return container;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized();
    // permission_handler: report every permission as granted.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => call.method == 'requestPermissions'
              ? {
                  for (final id in (call.arguments as List).cast<int>())
                    id: PermissionStatusValue.granted,
                }
              : null,
        );
  });

  for (final (name, mtuFails) in [
    ('the car\'s service is missing', false),
    ('the MTU request fails', true),
  ]) {
    testWidgets('drops the link and retries when $name', (tester) async {
      final ble = _FakeBle(mtuFails: mtuFails);
      final container = _container(ble);
      container.listen(bleConnectionProvider, (_, _) {});

      await tester.pump(const Duration(seconds: 1));
      expect(ble.connectCalls, 1);
      expect(ble.disconnects, 1, reason: 'the half-set-up link is dropped');
      expect(container.read(bleConnectionProvider), isA<BleConnecting>());

      await tester.pump(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      expect(ble.connectCalls, 2);
      expect(ble.disconnects, 2);

      // Disposing cancels the pending retry; the test binding checks for it.
      container.dispose();
    });
  }

  testWidgets('a link with the car\'s service becomes ready', (tester) async {
    final ble = _FakeBle(hasCarService: true);
    final container = _container(ble);
    container.listen(bleConnectionProvider, (_, _) {});

    await tester.pump(const Duration(seconds: 1));
    final state = container.read(bleConnectionProvider);
    expect(state, isA<BleReady>());
    expect((state as BleReady).attMtu, egmp.kBleAttMtu);
    container.dispose();
  });

  testWidgets('an MTU below the contract minimum fails the setup', (
    tester,
  ) async {
    // Android reports MTU 0 when the link dropped during the exchange.
    final ble = _FakeBle(hasCarService: true, mtu: 0);
    final container = _container(ble);
    container.listen(bleConnectionProvider, (_, _) {});

    await tester.pump(const Duration(seconds: 1));
    expect(container.read(bleConnectionProvider), isA<BleConnecting>());
    expect(ble.discoverCalls, 0);
    expect(ble.disconnects, 1, reason: 'the unusable link is dropped');

    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1));
    expect(ble.connectCalls, 2, reason: 'and retried');
    container.dispose();
  });

  testWidgets('a link that drops during setup is abandoned, then retried', (
    tester,
  ) async {
    final gate = Completer<void>();
    final ble = _FakeBle(hasCarService: true, mtuGate: gate);
    final container = _container(ble);
    container.listen(bleConnectionProvider, (_, _) {});
    await tester.pump(const Duration(seconds: 1));

    // The device hangs up while the MTU request is still pending, and the
    // request then completes as if nothing happened.
    ble.dropLink();
    await tester.pump();
    gate.complete();
    await tester.pump(const Duration(seconds: 1));

    expect(
      container.read(bleConnectionProvider),
      isA<BleConnecting>(),
      reason: 'the stale setup must not report BleReady',
    );
    expect(ble.discoverCalls, 0, reason: 'no discovery on the dead link');

    // The retry the stream's end scheduled still runs, and that link works.
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(ble.connectCalls, 2);
    expect(container.read(bleConnectionProvider), isA<BleReady>());
    container.dispose();
  });

  testWidgets('repeated drops right after connecting report a lost bond', (
    tester,
  ) async {
    // The MTU request failing stands in for the device dropping the link.
    final ble = _FakeBle(mtuFails: true);
    final container = _container(ble);
    container.listen(bleConnectionProvider, (_, _) {});

    await tester.pump(const Duration(seconds: 1));
    expect(container.read(bleBondLostProvider), isFalse, reason: 'one drop');

    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1));
    expect(ble.connectCalls, 2);
    expect(container.read(bleBondLostProvider), isTrue);

    // Unpairing clears it.
    await container.read(pairedVehicleProvider.notifier).unpair();
    expect(container.read(bleBondLostProvider), isFalse);
    container.dispose();
  });

  testWidgets('drops during setup with the pairing window open count', (
    tester,
  ) async {
    // As seen on a Pixel with the window open: the device drops the link
    // during the MTU exchange (Authentication Failure), and Android then
    // reports MTU 0 instead of failing the request.
    final gate = Completer<void>();
    final ble = _FakeBle(hasCarService: true, mtu: 0, mtuGate: gate);
    final container = _container(ble);
    container.listen(bleConnectionProvider, (_, _) {});
    await tester.pump(const Duration(seconds: 1));

    ble.dropLink();
    await tester.pump();
    gate.complete();
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(bleBondLostProvider), isFalse, reason: 'one drop');

    // The retry makes a second link, whose MTU of 0 fails the setup.
    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(ble.connectCalls, 2);
    expect(container.read(bleBondLostProvider), isTrue);
    container.dispose();
  });

  testWidgets('connections refused before connecting count', (tester) async {
    // With the pairing window closed the firmware hangs up on an unknown
    // phone before Android reports `connected`.
    final ble = _FakeBle(refuseAfter: const Duration(milliseconds: 100));
    final container = _container(ble);
    container.listen(bleConnectionProvider, (_, _) {});

    await tester.pump(const Duration(seconds: 1));
    expect(container.read(bleBondLostProvider), isFalse, reason: 'one drop');

    await tester.pump(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(ble.connectCalls, 2);
    expect(container.read(bleBondLostProvider), isTrue);
    container.dispose();
  });

  testWidgets('attempts that time out out of range do not count', (
    tester,
  ) async {
    final ble = _FakeBle(refuseAfter: const Duration(seconds: 30));
    final container = _container(ble);
    container.listen(bleConnectionProvider, (_, _) {});

    // Three attempts (at 0, 60 and 120 s), each 30 s connecting.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 30));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(ble.connectCalls, 3);
    expect(container.read(bleBondLostProvider), isFalse);
    container.dispose();
  });

  testWidgets('a missing service is not reported as a lost bond', (
    tester,
  ) async {
    final ble = _FakeBle();
    final container = _container(ble);
    container.listen(bleConnectionProvider, (_, _) {});

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1));
    expect(ble.connectCalls, 2);
    expect(container.read(bleBondLostProvider), isFalse);
    container.dispose();
  });

  testWidgets('pull-to-refresh reconnects at once while BLE is not ready', (
    tester,
  ) async {
    final ble = _FakeBle();
    final container = _container(ble);
    container.listen(bleConnectionProvider, (_, _) {});

    await tester.pump(const Duration(seconds: 1));
    expect(ble.connectCalls, 1);
    // Setup failed and a retry is pending in 30 s; the transport is MQTT.
    expect(container.read(bleConnectionProvider), isA<BleConnecting>());

    final pull = container.read(bleConnectionProvider.notifier).pullToRefresh();
    await tester.pump(const Duration(seconds: 1));
    await pull;
    expect(ble.connectCalls, 2, reason: 'the pull connects without waiting');

    // The pull replaced the retry due at 31 s instead of adding a second one.
    await tester.pump(const Duration(seconds: 25));
    expect(ble.connectCalls, 2);
    container.dispose();
  });

  testWidgets('pull-to-refresh does nothing for a vehicle paired over HTTP', (
    tester,
  ) async {
    final ble = _FakeBle();
    final container = _container(ble, preference: TransportPreference.http);
    container.listen(bleConnectionProvider, (_, _) {});

    final pull = container.read(bleConnectionProvider.notifier).pullToRefresh();
    await tester.pump(const Duration(seconds: 1));
    await pull;
    expect(ble.connectCalls, 0);
    container.dispose();
  });
}

/// permission_handler's `PermissionStatus.granted` as sent over its channel.
abstract final class PermissionStatusValue {
  static const granted = 1;
}
