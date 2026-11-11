import 'package:open_car_app/cars/egmp/state_access.dart';
import 'package:open_car_app/cars/egmp/widgets/chart_tiles.dart';
import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/widgets/tiles/history_chart.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

int? _powerWatts(VehicleSnapshot s) => switch (egmpAdvanced(s)) {
  final a? when a.hasInstantaneousPowerWatt() => a.instantaneousPowerWatt,
  _ => null,
};

final _powerSeries = HistorySeries(
  id: 'battery_power',
  sample: (s) => _powerWatts(s)?.toDouble(),
);

TileValue? _powerValue(VehicleSnapshot s) {
  final watts = _powerWatts(s);
  if (watts == null) return null;
  return TileValue.formatted(
    formatKilowatts(watts.abs()),
    note: watts > 0
        ? 'charging'
        : watts < 0
        ? 'discharging'
        : 'idle',
  );
}

/// The battery's power in and out, over time.
final egmpPowerChartTile = ChartTileDefinition(
  id: 'battery_power',
  label: 'Power',
  accessibleLabel: 'Battery power',
  tier: TileTier.advanced,
  sizes: const [TileSpan(2, 1), TileSpan(2, 2), TileSpan(4, 2)],
  series: [_powerSeries],
  describe: (data) => _powerValue(data.snapshot)?.toString() ?? 'unknown',
  builder: (context, data) => EgmpChartTile(
    label: 'Power',
    value: _powerValue(data.snapshot),
    span: data.span,
    chart: HistoryChart(lines: [samplesIn(data, _powerSeries)], fromZero: true),
  ),
);
