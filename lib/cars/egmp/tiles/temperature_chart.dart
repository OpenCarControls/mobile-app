import 'package:open_car_app/cars/egmp/state_access.dart';
import 'package:open_car_app/cars/egmp/widgets/chart_tiles.dart';
import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/widgets/tiles/history_chart.dart';

final _insideSeries = HistorySeries(
  id: 'inside_temperature',
  sample: (s) => egmpBasic(s).hasIndoorTemperature()
      ? egmpBasic(s).indoorTemperature
      : null,
);

final _outsideSeries = HistorySeries(
  id: 'outside_temperature',
  sample: (s) => egmpBasic(s).hasOutdoorTemperature()
      ? egmpBasic(s).outdoorTemperature
      : null,
);

/// The cabin temperature in the car's unit, with the outside one as the note
/// ("19.5 °C", "outside 12.0°C").
TileValue? _temperature(VehicleSnapshot s, TemperatureUnit unit) {
  final inside = _insideSeries.sample(s);
  if (inside == null) return null;
  final outside = _outsideSeries.sample(s);
  final note = outside == null
      ? null
      : 'outside ${formatTemperature(outside, unit)}';
  return switch (unit) {
    TemperatureUnit.celsius => TileValue(
      inside.toStringAsFixed(1),
      unit: '°C',
      note: note,
    ),
    TemperatureUnit.fahrenheit => TileValue(
      celsiusToFahrenheit(inside).round().toString(),
      unit: '°F',
      note: note,
    ),
  };
}

/// The cabin and outside temperatures, over time. Stands in for the climate
/// tile while the climate command isn't implemented.
final egmpTemperatureChartTile = ChartTileDefinition(
  id: 'temperature',
  label: 'Temperature',
  accessibleLabel: 'Cabin temperature',
  tier: TileTier.basic,
  series: [_insideSeries, _outsideSeries],
  describe: (data) =>
      _temperature(data.snapshot, data.units.temperature)?.toString() ??
      'unknown',
  builder: (context, data) => EgmpChartTile(
    label: 'Inside',
    value: _temperature(data.snapshot, data.units.temperature),
    span: data.span,
    chart: HistoryChart(
      lines: [samplesIn(data, _insideSeries), samplesIn(data, _outsideSeries)],
    ),
  ),
);
