import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/egmp/command_ids.dart' as egmp;
import 'package:open_car_app/cars/virtual_car/command_ids.dart' as virtual_car;
import 'package:open_car_app/cars/virtual_car/constants.g.dart'
    as virtual_car_constants;
import 'package:open_car_app/cars/virtual_car/screens/virtual_car_dashboard.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart'
    as egmp_pb;
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart'
    as virtual_car_pb;
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';

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

const _config = PairedVehicleConfig(
  vehicleId: virtual_car_constants.kPlatformName,
  bleRemoteId: '00:11:22:33:44:55',
  transportPreference: TransportPreference.ble,
);

const _available =
    CommandAvailabilityState.COMMAND_AVAILABILITY_STATE_AVAILABLE;
const _unavailable =
    CommandAvailabilityState.COMMAND_AVAILABILITY_STATE_UNAVAILABLE;
const _unsupported =
    CommandAvailabilityState.COMMAND_AVAILABILITY_STATE_UNSUPPORTED;

DeviceToApp _update(
  CommandAvailability availability, {
  int platformId = virtual_car_constants.kPlatformId,
}) => DeviceToApp(
  platformId: platformId,
  stateUpdate: StateUpdate(
    systemState: SystemState(commandAvailability: availability),
  ),
);

ProviderContainer _container(_FakeTransport transport) {
  final container = ProviderContainer(
    overrides: [
      bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
      initialPairedVehicleConfigProvider.overrideWithValue(_config),
      carTransportProvider.overrideWithValue(transport),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(transport.dispose);
  container.listen(vehicleStateProvider, (_, _) {});
  container.listen(commandAvailabilityProvider, (_, _) {});
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('command ids', () {
    test('are the field numbers on the wire', () {
      int firstField(List<int> bytes) => bytes.first >> 3;
      expect(
        egmp.kDoorLockCommand.id,
        firstField(
          egmp_pb.BasicCommand(
            doorLockCommand: egmp_pb.DoorLockCommand(lock: true),
          ).writeToBuffer(),
        ),
      );
      expect(
        egmp.kClimateControlCommand.id,
        firstField(
          egmp_pb.BasicCommand(
            climateControlCommand: egmp_pb.ClimateControlCommand(),
          ).writeToBuffer(),
        ),
      );
      expect(
        egmp.kBatteryPreconditioningCommand.id,
        firstField(
          egmp_pb.AdvancedCommand(
            batteryPreconditioningCommand:
                egmp_pb.BatteryPreconditioningCommand(enable: true),
          ).writeToBuffer(),
        ),
      );
      expect(
        virtual_car.kDoorLockCommand.id,
        firstField(
          virtual_car_pb.BasicCommand(
            doorLock: virtual_car_pb.DoorLockCommand(lock: true),
          ).writeToBuffer(),
        ),
      );
    });

    test('match the ids the firmware reports', () {
      // The firmware's `command_id` constants: the field numbers in egmp.proto.
      expect(egmp.kDoorLockCommand.id, 1);
      expect(egmp.kChargePortCommand.id, 2);
      expect(egmp.kFlashLightsCommand.id, 3);
      expect(egmp.kClimateControlCommand.id, 4);
      expect(egmp.kWindowCommand.id, 5);
      expect(egmp.kBatteryPreconditioningCommand.id, 1);
    });

    test('every dashboard button maps to a command', () {
      expect(egmp.egmpActionCommand('lock'), egmp.kDoorLockCommand);
      expect(egmp.egmpActionCommand('charge_port'), egmp.kChargePortCommand);
      expect(egmp.egmpActionCommand('lights'), egmp.kFlashLightsCommand);
      expect(egmp.egmpActionCommand('window_vent'), egmp.kWindowCommand);
      for (final climate in [
        'climate',
        'climate_power',
        'temp_down',
        'temp_up',
        'windshield_defrost',
        'rear_defrost',
        'steering_heater',
        'driver_seat',
        'passenger_seat',
      ]) {
        expect(egmp.egmpActionCommand(climate), egmp.kClimateControlCommand);
      }
    });

    test('an unknown field name is an error', () {
      expect(
        () => commandId(egmp_pb.BasicCommand(), 'noSuchCommand'),
        throwsArgumentError,
      );
    });
  });

  group('commandUiState', () {
    final reported = CommandAvailability(
      basic: {1: _available, 2: _unavailable, 3: _unsupported},
      advanced: {1: _unavailable},
    );

    CommandUiState state(
      CommandAvailability? r,
      TransportType t,
      CommandSet set,
      int id,
    ) => commandUiState(r, t, set, id);

    test('follows what the device reported', () {
      const ble = TransportType.ble;
      expect(state(reported, ble, CommandSet.basic, 1), CommandUiState.enabled);
      expect(
        state(reported, ble, CommandSet.basic, 2),
        CommandUiState.disabled,
      );
      expect(state(reported, ble, CommandSet.basic, 3), CommandUiState.hidden);
      expect(
        state(reported, ble, CommandSet.advanced, 1),
        CommandUiState.disabled,
      );
    });

    test('over BLE and MQTT, anything not reported is greyed out', () {
      for (final t in [TransportType.ble, TransportType.mqtt]) {
        expect(state(null, t, CommandSet.basic, 1), CommandUiState.disabled);
        // A command the device did not list.
        expect(
          state(reported, t, CommandSet.basic, 99),
          CommandUiState.disabled,
        );
      }
    });

    test('an unspecified state is not available', () {
      final r = CommandAvailability(
        basic: {
          1: CommandAvailabilityState.COMMAND_AVAILABILITY_STATE_UNSPECIFIED,
        },
      );
      expect(
        state(r, TransportType.ble, CommandSet.basic, 1),
        CommandUiState.disabled,
      );
    });

    test('on the debug transports, the device decides', () {
      for (final t in [TransportType.stub, TransportType.http]) {
        expect(state(null, t, CommandSet.basic, 1), CommandUiState.enabled);
      }
    });
  });

  group('commandAvailabilityProvider', () {
    test('is null until the device reports it on this connection', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      expect(container.read(commandAvailabilityProvider), isNull);
      expect(
        container.read(commandUiStateProvider(egmp.kDoorLockCommand)),
        CommandUiState.disabled,
      );

      transport.emit(_update(CommandAvailability(basic: {1: _available})));
      await pumpEventQueue();
      expect(
        container.read(commandUiStateProvider(virtual_car.kDoorLockCommand)),
        CommandUiState.enabled,
      );
    });

    test('merges a partial report per command', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(
        _update(CommandAvailability(basic: {1: _available, 2: _available})),
      );
      transport.emit(_update(CommandAvailability(basic: {2: _unavailable})));
      await pumpEventQueue();
      final state = container.read(commandAvailabilityProvider)!;
      expect(state.basic[1], _available);
      expect(state.basic[2], _unavailable);
    });

    test('a command that became unavailable is greyed out again', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(_update(CommandAvailability(basic: {1: _available})));
      await pumpEventQueue();
      transport.emit(_update(CommandAvailability(basic: {1: _unavailable})));
      await pumpEventQueue();
      expect(
        container.read(commandUiStateProvider(virtual_car.kDoorLockCommand)),
        CommandUiState.disabled,
      );
    });

    test('ignores updates that carry no availability', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(
        DeviceToApp(
          platformId: virtual_car_constants.kPlatformId,
          stateUpdate: StateUpdate(systemState: SystemState(uptimeS: 5)),
        ),
      );
      await pumpEventQueue();
      expect(container.read(commandAvailabilityProvider), isNull);
    });

    test('ignores a device reporting another platform', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(
        _update(
          CommandAvailability(basic: {1: _available}),
          platformId: virtual_car_constants.kPlatformId + 1,
        ),
      );
      await pumpEventQueue();
      expect(container.read(commandAvailabilityProvider), isNull);
    });

    test('is reported over MQTT too, for the basic commands', () async {
      final transport = _FakeTransport(TransportType.mqtt);
      final container = _container(transport);
      expect(
        container.read(commandUiStateProvider(egmp.kDoorLockCommand)),
        CommandUiState.disabled,
      );
      transport.emit(
        _update(CommandAvailability(basic: {1: _available, 2: _unavailable})),
      );
      await pumpEventQueue();
      expect(
        container.read(commandUiStateProvider(egmp.kDoorLockCommand)),
        CommandUiState.enabled,
      );
      expect(
        container.read(commandUiStateProvider(egmp.kChargePortCommand)),
        CommandUiState.disabled,
      );
    });

    test('ignores a cached availability', () async {
      // Cached by an earlier session, when everything was available. The
      // buttons must wait for the device to say so on this connection.
      final cached = SystemState(
        commandAvailability: CommandAvailability(basic: {1: _available}),
      );
      SharedPreferences.setMockInitialValues({
        'vehicle_state_${virtual_car_constants.kPlatformName}': jsonEncode({
          'basicStateBytes': '',
          'advancedStateBytes': '',
          'systemStateBytes': base64Encode(cached.writeToBuffer()),
        }),
      });
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      await pumpEventQueue();
      expect(
        container.read(vehicleStateProvider).system?.hasCommandAvailability(),
        isTrue,
      );
      expect(container.read(commandAvailabilityProvider), isNull);
      expect(
        container.read(commandUiStateProvider(virtual_car.kDoorLockCommand)),
        CommandUiState.disabled,
      );

      // A live vehicle state update doesn't make the cached one current.
      transport.emit(
        DeviceToApp(
          platformId: virtual_car_constants.kPlatformId,
          stateUpdate: StateUpdate(vehicleState: VehicleState()),
        ),
      );
      await pumpEventQueue();
      expect(container.read(vehicleStateProvider).isStateLive, isTrue);
      expect(container.read(commandAvailabilityProvider), isNull);
    });

    testWidgets('is cleared when the device goes quiet', (tester) async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(_update(CommandAvailability(basic: {1: _available})));
      await tester.pump();
      expect(container.read(commandAvailabilityProvider), isNotNull);

      await tester.pump(
        kCommandAvailabilityStaleAfter - const Duration(seconds: 1),
      );
      expect(container.read(commandAvailabilityProvider), isNotNull);

      await tester.pump(const Duration(seconds: 2));
      expect(container.read(commandAvailabilityProvider), isNull);
      expect(
        container.read(commandUiStateProvider(virtual_car.kDoorLockCommand)),
        CommandUiState.disabled,
      );
      // Let vehicleStateProvider's own liveness timer run out.
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('over MQTT it expires with the vehicle state, not sooner', (
      tester,
    ) async {
      final transport = _FakeTransport(TransportType.mqtt);
      final container = _container(transport);
      transport.emit(_update(CommandAvailability(basic: {1: _available})));
      await tester.pump();
      expect(
        commandAvailabilityStaleAfter(TransportType.mqtt),
        kStateLivenessTimeout,
      );

      // Past the BLE window: MQTT is slower, so it is still trusted.
      await tester.pump(
        kCommandAvailabilityStaleAfter + const Duration(seconds: 5),
      );
      expect(container.read(commandAvailabilityProvider), isNotNull);
      expect(
        container.read(commandUiStateProvider(egmp.kDoorLockCommand)),
        CommandUiState.enabled,
      );

      await tester.pump(kStateLivenessTimeout - kCommandAvailabilityStaleAfter);
      expect(container.read(commandAvailabilityProvider), isNull);
      expect(
        container.read(commandUiStateProvider(egmp.kDoorLockCommand)),
        CommandUiState.disabled,
      );
      await tester.pump(const Duration(seconds: 31));
    });

    test('BLE keeps the shorter window', () {
      expect(
        commandAvailabilityStaleAfter(TransportType.ble),
        kCommandAvailabilityStaleAfter,
      );
      expect(kCommandAvailabilityStaleAfter < kStateLivenessTimeout, isTrue);
    });

    testWidgets('each report keeps it alive', (tester) async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      for (var i = 0; i < 4; i++) {
        transport.emit(_update(CommandAvailability(basic: {1: _available})));
        await tester.pump(const Duration(seconds: 10));
      }
      expect(container.read(commandAvailabilityProvider), isNotNull);
      await tester.pump(const Duration(seconds: 31));
    });
  });

  group('virtual car dashboard', () {
    Future<_FakeTransport> pump(WidgetTester tester) async {
      final transport = _FakeTransport(TransportType.ble);
      addTearDown(transport.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
            initialPairedVehicleConfigProvider.overrideWithValue(_config),
            carTransportProvider.overrideWithValue(transport),
          ],
          child: const MaterialApp(home: VirtualCarDashboardScreen()),
        ),
      );
      await tester.pump();
      return transport;
    }

    VoidCallback? doorButton(WidgetTester tester) {
      final button = find.ancestor(
        of: find.textContaining(RegExp('^(Lock|Unlock)\$')),
        matching: find.byType(ElevatedButton),
      );
      return tester.widget<ElevatedButton>(button).onPressed;
    }

    testWidgets('greys the door button out unless the device accepts it', (
      tester,
    ) async {
      final transport = await pump(tester);
      // Nothing reported yet over BLE.
      expect(doorButton(tester), isNull);

      transport.emit(_update(CommandAvailability(basic: {1: _available})));
      await tester.pump();
      expect(doorButton(tester), isNotNull);

      transport.emit(_update(CommandAvailability(basic: {1: _unavailable})));
      await tester.pump();
      expect(doorButton(tester), isNull);

      // The device went quiet: back to greyed out, not the last value.
      transport.emit(_update(CommandAvailability(basic: {1: _available})));
      await tester.pump();
      expect(doorButton(tester), isNotNull);
      await tester.pump(kCommandAvailabilityStaleAfter);
      await tester.pump();
      expect(doorButton(tester), isNull);

      // Dispose the providers, which cancels the state liveness timer.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('hides a command the car does not have', (tester) async {
      final transport = await pump(tester);
      transport.emit(_update(CommandAvailability(basic: {1: _unsupported})));
      await tester.pump();
      expect(find.text('Doors'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
