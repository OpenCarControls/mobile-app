import 'dart:async';

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
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';

class _FakeTransport implements CarTransport {
  final _controller = StreamController<DeviceToApp>.broadcast();
  final sent = <AppToDevice>[];

  void emit(DeviceToApp msg) => _controller.add(msg);

  @override
  TransportType get transportType => TransportType.stub;

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

void main() {
  late _FakeTransport transport;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    transport = _FakeTransport();
    container = ProviderContainer(
      overrides: [
        bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
        initialPairedVehicleConfigProvider.overrideWithValue(
          _config(virtual_car.kPlatformName),
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

    await expectLater(future, throwsA('Door is open'));
  });

  test('selectedVehicleProvider is null for an unknown vehicle id', () {
    final c = ProviderContainer(
      overrides: [
        initialPairedVehicleConfigProvider.overrideWithValue(
          _config('opencar.cars.unknown.v1'),
        ),
      ],
    );
    addTearDown(c.dispose);

    expect(c.read(selectedVehicleProvider), isNull);
  });
}
