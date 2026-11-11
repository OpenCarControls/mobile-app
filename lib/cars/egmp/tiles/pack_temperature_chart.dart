import 'package:open_car_app/cars/egmp/state_access.dart';
import 'package:open_car_app/cars/egmp/widgets/chart_tiles.dart';
import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/widgets/tiles/history_chart.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

final _packMinSeries = HistorySeries(
  id: 'pack_temperature_min',
  sample: (s) => switch (egmpAdvanced(s)) {
    final a? when a.hasBatteryMinimumTemperature() =>
      a.batteryMinimumTemperature,
    _ => null,
  },
);

final _packMaxSeries = HistorySeries(
  id: 'pack_temperature_max',
  sample: (s) => switch (egmpAdvanced(s)) {
    final a? when a.hasBatteryMaximumTemperature() =>
      a.batteryMaximumTemperature,
    _ => null,
  },
);

/// The pack's temperature range in the car's unit ("24–27 °C").
TileValue? _packTemperature(VehicleSnapshot s, TemperatureUnit unit) {
  final low = _packMinSeries.sample(s);
  final high = _packMaxSeries.sample(s);
  if (low == null || high == null) return null;
  String degrees(double c) => switch (unit) {
    TemperatureUnit.celsius => c.round().toString(),
    TemperatureUnit.fahrenheit => celsiusToFahrenheit(c).round().toString(),
  };
  final range = degrees(low) == degrees(high)
      ? degrees(low)
      : '${degrees(low)}–${degrees(high)}';
  return TileValue(range, unit: unit == TemperatureUnit.celsius ? '°C' : '°F');
}

/// The pack's coldest and warmest module, over time.
final egmpPackTemperatureChartTile = ChartTileDefinition(
  id: 'pack_temperature',
  label: 'Pack temp',
  accessibleLabel: 'Battery temperature',
  tier: TileTier.advanced,
  sizes: const [TileSpan(2, 1), TileSpan(2, 2)],
  series: [_packMinSeries, _packMaxSeries],
  describe: (data) =>
      _packTemperature(data.snapshot, data.units.temperature)?.toString() ??
      'unknown',
  builder: (context, data) => EgmpChartTile(
    label: 'Pack temp',
    value: _packTemperature(data.snapshot, data.units.temperature),
    span: data.span,
    chart: HistoryChart(
      lines: [samplesIn(data, _packMinSeries), samplesIn(data, _packMaxSeries)],
    ),
  ),
);
