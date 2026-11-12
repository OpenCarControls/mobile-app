import 'package:material_ui/material_ui.dart';

import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/tiles/history_chart.dart';
import 'package:open_car_app/widgets/tiles/state_tile.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

/// The header of an E-GMP chart tile: the label, a value with its unit and
/// an optional note, over the [chart]. At one row the chart sits beside it.
class EgmpChartTile extends StatelessWidget {
  const EgmpChartTile({
    super.key,
    required this.label,
    required this.value,
    required this.chart,
    required this.span,
  });

  final String label;
  final TileValue? value;
  final HistoryChart chart;
  final TileSpan span;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final large = span.rows >= 2;
    final value = this.value;
    final text = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: tokens.textSecondary)),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value?.value ?? kNoValue,
                  style: large
                      ? AppTextStyles.statValue.copyWith(
                          fontSize: 36,
                          height: 1.1,
                        )
                      : AppTextStyles.statValue,
                ),
                if (value?.unit case final unit?)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(fontSize: large ? 16 : 13),
                  ),
              ],
            ),
          ),
          if (large && value?.note != null)
            Text(value!.note!, style: TextStyle(color: tokens.textSecondary)),
        ],
      ),
    );
    if (large) {
      return TextOverChart(text: text, chart: chart);
    }
    return Row(
      children: [
        Flexible(child: text),
        const SizedBox(width: 12),
        Expanded(child: chart),
      ],
    );
  }
}

/// The samples of [series] in [data], or none.
List<HistorySample> samplesIn(ChartTileData data, HistorySeries series) =>
    data.history[series.id] ?? const [];
