import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/cars/virtual_car/virtual_car_definition.dart';
import 'package:open_car_app/generated/opencar/cars/virtual_car/v1/virtual_car.pb.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_history_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

final _odometer = HistorySeries(
  id: 'odometer',
  sample: (s) => (s.basicState as BasicState).hasOdometer()
      ? (s.basicState as BasicState).odometer.toDouble()
      : null,
);

/// The virtual car with one chart of its odometer.
class _ChartedCar extends VirtualCarDefinition {
  const _ChartedCar();

  @override
  List<TileDefinition> get tiles => [
    ChartTileDefinition(
      id: 'odometer',
      label: 'Odometer',
      tier: TileTier.basic,
      series: [_odometer],
      describe: (_) => '',
      builder: (_, _) => const SizedBox(),
    ),
  ];
}

/// A vehicle state set by the test.
class _FakeState extends VehicleStateNotifier {
  @override
  VehicleSnapshot build() =>
      VehicleSnapshot(basicState: BasicState(), advancedState: AdvancedState());

  void set({required int odometer, bool live = true}) =>
      state = VehicleSnapshot(
        basicState: BasicState(odometer: odometer),
        advancedState: AdvancedState(),
        isStateLive: live,
      );
}

void main() {
  group('HistoryBuffer', () {
    final t0 = DateTime(2026, 11, 7, 12);

    test('keeps one sample per interval, with the latest value', () {
      final buffer = HistoryBuffer(interval: const Duration(seconds: 5));
      buffer.add(t0, 1);
      buffer.add(t0.add(const Duration(seconds: 2)), 2);
      buffer.add(t0.add(const Duration(seconds: 6)), 3);
      expect(buffer.samples, [
        (time: t0, value: 2.0),
        (time: t0.add(const Duration(seconds: 6)), value: 3.0),
      ]);
    });

    test('drops samples older than the window', () {
      final buffer = HistoryBuffer(window: const Duration(minutes: 1));
      buffer.add(t0, 1);
      buffer.add(t0.add(const Duration(seconds: 30)), 2);
      buffer.add(t0.add(const Duration(seconds: 61)), 3);
      expect([for (final s in buffer.samples) s.value], [2.0, 3.0]);
    });
  });

  test('the history records live state of the catalog series', () {
    final container = ProviderContainer(
      overrides: [
        selectedVehicleProvider.overrideWithValue(const _ChartedCar()),
        vehicleStateProvider.overrideWith(_FakeState.new),
      ],
    );
    addTearDown(container.dispose);
    var time = DateTime(2026, 11, 7, 12);
    container.read(vehicleHistoryProvider.notifier).now = () => time;
    final state = container.read(vehicleStateProvider.notifier) as _FakeState;

    state.set(odometer: 10, live: false);
    expect(container.read(vehicleHistoryProvider), isEmpty);

    state.set(odometer: 11);
    time = time.add(const Duration(minutes: 1));
    state.set(odometer: 12);
    final samples = container.read(vehicleHistoryProvider)['odometer']!;
    expect([for (final s in samples) s.value], [11.0, 12.0]);
  });
}
