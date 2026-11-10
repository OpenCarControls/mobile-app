import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/egmp/constants.g.dart' as egmp;
import 'package:open_car_app/cars/virtual_car/constants.g.dart' as virtual_car;
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/config/vehicle_state_cache_config.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart'
    as egmp_pb;
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/providers/vehicle_summary_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/transport/mqtt_transport.dart';

class _FakeTransport implements CarTransport {
  _FakeTransport([this.transportType = TransportType.stub]);

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

PairedVehicleConfig _config(String vehicleId) => PairedVehicleConfig(
  vehicleId: vehicleId,
  bleRemoteId: '00:11:22:33:44:55',
  transportPreference: TransportPreference.ble,
);

DeviceToApp _stateUpdate({required int platformId, required int odometer}) =>
    DeviceToApp(
      platformId: platformId,
      stateUpdate: StateUpdate(
        vehicleState: VehicleState(
          basicStateBytes: BasicState(odometer: odometer).writeToBuffer(),
        ),
      ),
    );

DeviceToApp _mqttClientIdUpdate({required int platformId}) => DeviceToApp(
  platformId: platformId,
  stateUpdate: StateUpdate(systemState: SystemState(mqttClientId: 'dev-car')),
);

void main() {
  late _FakeTransport transport;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    transport = _FakeTransport();
    container = ProviderContainer(
      overrides: [
        bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
        initialPairedVehiclesProvider.overrideWithValue(
          PairedVehicles.of(_config(virtual_car.kPlatformName)),
        ),
        carTransportProvider.overrideWithValue(transport),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(transport.dispose);
    // Keep the provider alive and subscribed to the transport.
    container.listen(vehicleStateProvider, (_, _) {});
  });

  test('merges state updates from the paired platform', () async {
    transport.emit(
      _stateUpdate(platformId: virtual_car.kPlatformId, odometer: 42),
    );
    await pumpEventQueue();

    final snapshot = container.read(vehicleStateProvider);
    expect((snapshot.basicState as BasicState).odometer, 42);
    expect(snapshot.isStateLive, isTrue);
    expect(snapshot.mismatchedPlatformId, isNull);
  });

  test('flags a platform mismatch without unpairing or applying it', () async {
    transport.emit(_stateUpdate(platformId: 0x1234, odometer: 99));
    await pumpEventQueue();

    final snapshot = container.read(vehicleStateProvider);
    expect(snapshot.mismatchedPlatformId, 0x1234);
    expect((snapshot.basicState as BasicState).hasOdometer(), isFalse);
    expect(container.read(pairedVehicleProvider), isNotNull);
  });

  test('completes a command with its matching response', () async {
    final future = container
        .read(vehicleStateProvider.notifier)
        .sendBasicCommand(const [1]);
    await pumpEventQueue();
    final messageId = transport.sent.single.messageId;

    transport.emit(
      DeviceToApp(
        commandResponse: CommandResponse(messageId: messageId, success: true),
      ),
    );

    expect((await future).messageId, messageId);
  });

  test('fails a command when the device reports an error', () async {
    final future = container
        .read(vehicleStateProvider.notifier)
        .sendBasicCommand(const [1]);
    await pumpEventQueue();

    transport.emit(
      DeviceToApp(
        commandResponse: CommandResponse(
          messageId: transport.sent.single.messageId,
          success: false,
          errorMessage: 'Door is open',
        ),
      ),
    );

    await expectLater(
      future,
      throwsA(
        isA<CommandRejectedException>().having(
          (e) => '$e',
          'text',
          'Door is open',
        ),
      ),
    );
  });

  group('the device\'s MQTT client ID', () {
    test('is remembered from the local link and stored', () async {
      transport.emit(_mqttClientIdUpdate(platformId: virtual_car.kPlatformId));
      await pumpEventQueue();

      expect(container.read(pairedVehicleProvider)?.mqttClientId, 'dev-car');
      expect((await PairedVehicles.load()).current?.mqttClientId, 'dev-car');
    });

    test('is ignored from a device on another platform', () async {
      transport.emit(
        _mqttClientIdUpdate(platformId: virtual_car.kPlatformId + 1),
      );
      await pumpEventQueue();

      expect(container.read(pairedVehicleProvider)?.mqttClientId, isNull);
    });

    test('is ignored over MQTT', () async {
      final mqtt = _FakeTransport(TransportType.mqtt);
      final c = ProviderContainer(
        overrides: [
          bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
          initialPairedVehiclesProvider.overrideWithValue(
            PairedVehicles.of(_config(virtual_car.kPlatformName)),
          ),
          carTransportProvider.overrideWithValue(mqtt),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(mqtt.dispose);
      c.listen(vehicleStateProvider, (_, _) {});

      mqtt.emit(_mqttClientIdUpdate(platformId: virtual_car.kPlatformId));
      await pumpEventQueue();

      expect(c.read(pairedVehicleProvider)?.mqttClientId, isNull);
    });
  });

  group('with two vehicles of the same platform', () {
    late ProviderContainer c;
    final transports = <_FakeTransport>[];

    PairedVehicleConfig vehicle(String id) => PairedVehicleConfig(
      id: id,
      vehicleId: virtual_car.kPlatformName,
      bleRemoteId: id,
      transportPreference: TransportPreference.ble,
    );

    int odometer() =>
        (c.read(vehicleStateProvider).basicState as BasicState).odometer;

    Future<void> switchTo(String id) async {
      await c.read(pairedVehiclesProvider.notifier).switchTo(id);
      await pumpEventQueue();
    }

    setUp(() {
      transports.clear();
      c = ProviderContainer(
        overrides: [
          bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
          initialPairedVehiclesProvider.overrideWithValue(
            PairedVehicles(
              vehicles: [vehicle('a'), vehicle('b')],
              currentId: 'a',
            ),
          ),
          carTransportProvider.overrideWith((ref) {
            ref.watch(pairedVehicleProvider.select((v) => v?.id));
            final transport = _FakeTransport();
            transports.add(transport);
            ref.onDispose(transport.dispose);
            return transport;
          }),
        ],
      );
      addTearDown(c.dispose);
      c.listen(vehicleStateProvider, (_, _) {});
    });

    test('each vehicle has its own link and restores its own state', () async {
      transports.last.emit(
        _stateUpdate(platformId: virtual_car.kPlatformId, odometer: 42),
      );
      await pumpEventQueue();
      expect(odometer(), 42);

      await switchTo('b');
      expect(transports, hasLength(2));
      expect(odometer(), 0);

      transports.last.emit(
        _stateUpdate(platformId: virtual_car.kPlatformId, odometer: 7),
      );
      await pumpEventQueue();
      expect(odometer(), 7);

      await switchTo('a');
      expect(odometer(), 42);
      expect(c.read(vehicleStateProvider).isStateLive, isFalse);
    });

    test('a platform mismatch stays with its vehicle', () async {
      transports.last.emit(
        _stateUpdate(platformId: virtual_car.kPlatformId + 1, odometer: 1),
      );
      await pumpEventQueue();
      expect(c.read(vehicleStateProvider).mismatchedPlatformId, isNotNull);

      await switchTo('b');
      expect(c.read(vehicleStateProvider).mismatchedPlatformId, isNull);
    });

    test('a vehicle not connected keeps its last update', () async {
      transports.last.emit(
        _stateUpdate(platformId: virtual_car.kPlatformId, odometer: 42),
      );
      await pumpEventQueue();
      await switchTo('b');

      final stored = await loadVehicleSummaries();
      expect(c.read(vehicleSummariesProvider)['a']?.lastUpdated, isNotNull);
      expect(stored['a']?.lastUpdated, isNotNull);
      expect(stored['b'], isNull);
    });
  });

  test('the last known level and range come from the energy store', () async {
    final link = _FakeTransport();
    final c = ProviderContainer(
      overrides: [
        bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
        initialPairedVehiclesProvider.overrideWithValue(
          PairedVehicles.of(_config(egmp.kPlatformName)),
        ),
        carTransportProvider.overrideWithValue(link),
      ],
    );
    addTearDown(c.dispose);
    addTearDown(link.dispose);
    c.listen(vehicleStateProvider, (_, _) {});

    link.emit(
      DeviceToApp(
        platformId: egmp.kPlatformId,
        stateUpdate: StateUpdate(
          vehicleState: VehicleState(
            basicStateBytes: egmp_pb.BasicState(
              batterySoc: 64,
              batteryRangeKm: 310,
            ).writeToBuffer(),
          ),
        ),
      ),
    );
    await pumpEventQueue();

    final summary = (await loadVehicleSummaries())[egmp.kPlatformName];
    expect(summary?.levelPercent, 64);
    expect(summary?.rangeKm, 310);
  });

  test('MQTT topics name the device', () {
    expect(
      mqttDeviceTopic('opencar/{client_id}/cmd', 'dev-car'),
      'opencar/dev-car/cmd',
    );
  });

  test('selectedVehicleProvider is null for an unknown vehicle id', () {
    final c = ProviderContainer(
      overrides: [
        initialPairedVehiclesProvider.overrideWithValue(
          PairedVehicles.of(_config('opencar.cars.unknown.v1')),
        ),
      ],
    );
    addTearDown(c.dispose);

    expect(c.read(selectedVehicleProvider), isNull);
  });
}
