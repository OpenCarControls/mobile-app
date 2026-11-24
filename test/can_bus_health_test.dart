import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/virtual_car/constants.g.dart' as virtual_car;
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/can_bus_health_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/can_bus_health_section.dart';

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
  vehicleId: virtual_car.kPlatformName,
  bleRemoteId: '00:11:22:33:44:55',
  transportPreference: TransportPreference.ble,
);

CanBusHealth _bus(
  CanBusStatus status, {
  int framesPerSecond = 0,
  int errors = 0,
  int overruns = 0,
}) {
  return CanBusHealth(
    status: status,
    listenOnly: true,
    framesPerSecond: framesPerSecond,
    rxErrors: errors,
    overruns: overruns,
    busOffs: 0,
  );
}

DeviceToApp _healthUpdate(Map<int, CanBusHealth> buses) => DeviceToApp(
  platformId: virtual_car.kPlatformId,
  stateUpdate: StateUpdate(
    systemState: SystemState(canBusHealth: buses.entries),
  ),
);

List<Override> _overrides(_FakeTransport transport) => [
  bleSourceDeviceIdProvider.overrideWithValue(const [1, 2, 3]),
  initialPairedVehiclesProvider.overrideWithValue(PairedVehicles.of(_config)),
  carTransportProvider.overrideWithValue(transport),
];

ProviderContainer _container(_FakeTransport transport) {
  final container = ProviderContainer(overrides: _overrides(transport));
  addTearDown(container.dispose);
  addTearDown(transport.dispose);
  container.listen(canBusHealthProvider, (_, _) {});
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('canBusHealthProvider', () {
    test('is null until the device reports it', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      expect(container.read(canBusHealthProvider), isNull);

      final ok = _bus(CanBusStatus.CAN_BUS_STATUS_OK, framesPerSecond: 10);
      transport.emit(_healthUpdate({0: ok}));
      await pumpEventQueue();
      final buses = container.read(canBusHealthProvider)!;
      expect(buses[0]!.status, CanBusStatus.CAN_BUS_STATUS_OK);
      expect(buses[0]!.framesPerSecond, 10);
    });

    test('replaces each reported bus and keeps the others', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      final first = {
        0: _bus(CanBusStatus.CAN_BUS_STATUS_OK, framesPerSecond: 10),
        1: _bus(CanBusStatus.CAN_BUS_STATUS_SILENT),
      };
      final second = {
        0: _bus(CanBusStatus.CAN_BUS_STATUS_NO_VALID_FRAMES, errors: 4),
      };
      transport.emit(_healthUpdate(first));
      transport.emit(_healthUpdate(second));
      await pumpEventQueue();
      final buses = container.read(canBusHealthProvider)!;
      expect(buses.length, 2);
      expect(buses[0]!.status, CanBusStatus.CAN_BUS_STATUS_NO_VALID_FRAMES);
      expect(buses[0]!.rxErrors, 4);
      expect(buses[1]!.status, CanBusStatus.CAN_BUS_STATUS_SILENT);
    });

    test('ignores system state without bus health', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      transport.emit(
        DeviceToApp(
          platformId: virtual_car.kPlatformId,
          stateUpdate: StateUpdate(
            systemState: SystemState(canAccess: CanAccessState()),
          ),
        ),
      );
      await pumpEventQueue();
      expect(container.read(canBusHealthProvider), isNull);
    });

    test('ignores a device reporting another platform', () async {
      final transport = _FakeTransport(TransportType.ble);
      final container = _container(transport);
      final update = _healthUpdate({0: _bus(CanBusStatus.CAN_BUS_STATUS_OK)});
      update.platformId = 7;
      transport.emit(update);
      await pumpEventQueue();
      expect(container.read(canBusHealthProvider), isNull);
    });

    test('is null over MQTT, which carries no system state', () async {
      final transport = _FakeTransport(TransportType.mqtt);
      final container = _container(transport);
      transport.emit(_healthUpdate({0: _bus(CanBusStatus.CAN_BUS_STATUS_OK)}));
      await pumpEventQueue();
      expect(container.read(canBusHealthProvider), isNull);
    });
  });

  group('wording', () {
    test('every status has a label and a hint', () {
      for (final status in CanBusStatus.values) {
        expect(canBusStatusLabel(status), isNotEmpty);
        expect(canBusStatusHint(status), isNotEmpty);
      }
      expect(canBusStatusLabel(CanBusStatus.CAN_BUS_STATUS_BUS_OFF), 'Bus-off');
    });

    test('counters read in one line, with the frame rate', () {
      final health = _bus(
        CanBusStatus.CAN_BUS_STATUS_DEGRADED,
        framesPerSecond: 2160,
        errors: 3,
        overruns: 1,
      );
      expect(
        canBusCounters(health),
        '2160 frames/s · 3 errors · 1 overruns · 0 bus-offs',
      );
    });
  });

  testWidgets('the section lists each bus by id', (tester) async {
    final transport = _FakeTransport(TransportType.ble);
    addTearDown(transport.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(transport),
        child: MaterialApp(
          theme: buildAppTheme(defaultSkin, Brightness.light),
          home: const Scaffold(body: CanBusHealthSection()),
        ),
      ),
    );
    expect(find.textContaining('Waiting for the device'), findsOneWidget);

    final buses = {
      1: _bus(CanBusStatus.CAN_BUS_STATUS_SILENT),
      0: _bus(CanBusStatus.CAN_BUS_STATUS_OK, framesPerSecond: 42),
    };
    transport.emit(_healthUpdate(buses));
    await tester.pumpAndSettle();
    expect(find.text('Bus 0 (listen-only)'), findsOneWidget);
    expect(find.text('Bus 1 (listen-only)'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(find.text('Silent'), findsOneWidget);
    expect(find.textContaining('42 frames/s'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Bus 0 (listen-only)')).dy,
      lessThan(tester.getTopLeft(find.text('Bus 1 (listen-only)')).dy),
    );

    await tester.pumpWidget(const SizedBox());
  });
}
