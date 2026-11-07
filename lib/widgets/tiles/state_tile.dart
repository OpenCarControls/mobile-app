import 'package:flutter/material.dart';

import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/tiles/history_chart.dart';
import 'package:open_car_app/widgets/tiles/tile_context.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';
import 'package:open_car_app/widgets/tiles/tile_surface.dart';

/// Shown for a value the vehicle doesn't report (yet).
const kNoValue = '—';

/// A value with its label. 2×1 adds a sparkline; 2×2 a large value, a note
/// and a chart.
class StateTile extends StatelessWidget {
  const StateTile({
    super.key,
    required this.tile,
    required this.span,
    required this.data,
  });

  final StateTileDefinition tile;
  final TileSpan span;
  final TileContext data;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final value = tile.value(data.snapshot, data.units);
    final samples = data.samplesOf(tile.history);
    final large = span.rows >= 2 && span.columns >= 2;
    final wide = span.columns >= 2;

    final label = Text(
      tile.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: tokens.textSecondary),
    );
    final valueStyle = large
        ? AppTextStyles.statValue.copyWith(fontSize: 36, height: 1.1)
        : AppTextStyles.statValue;
    final valueText = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: value?.value ?? kNoValue, style: valueStyle),
          if (value?.unit case final unit?)
            TextSpan(
              text: ' $unit',
              style: TextStyle(fontSize: large ? 16 : 13),
            ),
        ],
      ),
      maxLines: 1,
    );
    final text = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          label,
          valueText,
          if (large && value?.note != null)
            Text(value!.note!, style: TextStyle(color: tokens.textSecondary)),
        ],
      ),
    );

    final Widget content;
    if (large) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: text),
          const SizedBox(height: 8),
          Expanded(child: HistoryChart(lines: [samples])),
        ],
      );
    } else if (wide && tile.history != null) {
      content = Row(
        children: [
          Flexible(child: text),
          const SizedBox(width: 12),
          Expanded(child: HistoryChart(lines: [samples])),
        ],
      );
    } else {
      content = Align(alignment: Alignment.centerLeft, child: text);
    }

    return Semantics(
      container: true,
      label: '${tile.accessibleLabel}, ${value ?? 'unknown'}',
      excludeSemantics: true,
      child: TileSurface(child: content),
    );
  }
}
