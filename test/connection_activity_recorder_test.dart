import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/cars/virtual_car/virtual_car_definition.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/connection_activity_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';

/// The link set by the test.
class _Link extends Notifier<TransportType> {
  @override
  TransportType build() => TransportType.mqtt;

  void set(TransportType link) => state = link;
}

final _linkProvider = NotifierProvider<_Link, TransportType>(_Link.new);

/// A vehicle state set by the test.
class _FakeState extends VehicleStateNotifier {
  @override
  VehicleSnapshot build() =>
      VehicleSnapshot(basicState: BasicState(), advancedState: AdvancedState());

  void set({required bool live, int odometer = 0}) => state = VehicleSnapshot(
    basicState: BasicState(odometer: odometer),
    advancedState: AdvancedState(),
    isStateLive: live,
  );
}

const _config = PairedVehicleConfig(
  vehicleId: 'virtual',
  bleRemoteId: 'AA:BB:CC:DD:EE:FF',
  transportPreference: TransportPreference.ble,
);

ProviderContainer _container({bool paired = true}) {
  final container = ProviderContainer(
    overrides: [
      initialPairedVehicleConfigProvider.overrideWithValue(
        paired ? _config : null,
      ),
      selectedVehicleProvider.overrideWithValue(
        paired ? const VirtualCarDefinition() : null,
      ),
      transportTypeProvider.overrideWith((ref) => ref.watch(_linkProvider)),
      vehicleStateProvider.overrideWith(_FakeState.new),
    ],
  );
  addTearDown(container.dispose);
  container.listen(connectionActivityRecorderProvider, (_, _) {});
  return container;
}

extension on ProviderContainer {
  void link(TransportType link) {
    read(_linkProvider.notifier).set(link);
    // Riverpod updates dependent providers lazily: this applies it now.
    read(transportTypeProvider);
  }

  void state({required bool live, int odometer = 0}) =>
      (read(vehicleStateProvider.notifier) as _FakeState).set(
        live: live,
        odometer: odometer,
      );

  /// The log, oldest first.
  List<String> get lines => [
    for (final entry in read(connectionActivityProvider).reversed) entry.title,
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Bluetooth coming up is logged', () {
    final container = _container();
    container.link(TransportType.ble);
    expect(container.lines, ['Bluetooth connected']);
  });

  test('losing Bluetooth is logged once, and remote waits for the vehicle', () {
    final container = _container();
    container.link(TransportType.ble);
    container.state(live: true);

    container.state(live: false);
    container.link(TransportType.mqtt);

    expect(container.lines, ['Bluetooth connected', 'Bluetooth link lost']);
  });

  test('remote connects when the vehicle answers over MQTT', () {
    final container = _container();
    expect(container.lines, isEmpty);

    container.state(live: true);

    expect(container.lines, ['Remote connected']);
  });

  test('state updates are not logged', () {
    final container = _container();
    container.state(live: true, odometer: 1);
    container.state(live: true, odometer: 2);
    container.state(live: true, odometer: 3);

    expect(container.lines, ['Remote connected']);
  });

  test('remote is logged again after the vehicle went quiet', () {
    final container = _container();
    container.state(live: true);
    container.state(live: false);
    container.state(live: true);

    expect(container.lines, ['Remote connected', 'Remote connected']);
  });

  test('live state over Bluetooth is not a remote connection', () {
    final container = _container();
    container.link(TransportType.ble);
    container.state(live: true);

    expect(container.lines, ['Bluetooth connected']);
  });

  test('the debug transports log nothing', () {
    final container = _container();
    container.link(TransportType.http);
    container.state(live: true);
    container.link(TransportType.stub);

    expect(container.lines, isEmpty);
  });

  test('records nothing without a vehicle', () {
    final container = _container(paired: false);
    container.link(TransportType.ble);

    expect(container.read(connectionActivityLogsProvider), isEmpty);
  });
}
