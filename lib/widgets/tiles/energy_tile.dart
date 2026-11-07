import 'package:flutter/material.dart';

import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/tiles/state_tile.dart';
import 'package:open_car_app/widgets/tiles/tile_context.dart';
import 'package:open_car_app/widgets/tiles/tile_surface.dart';

/// A power in kW with one decimal ("7.2 kW").
String formatKilowatts(int watts) => '${(watts / 1000).toStringAsFixed(1)} kW';

/// The Battery or Fuel tile: the level bar with a tick at the charge limit,
/// over a line that depends on the state. Idle, it gives the level and the
/// range; charging, the power and the time to the limit; exporting (V2L), the
/// power going out.
class EnergyTile extends StatelessWidget {
  const EnergyTile({super.key, required this.tile, required this.data});

  final EnergyTileDefinition tile;
  final TileContext data;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final snapshot = data.snapshot;
    final energy = tile.energy;
    final level = energy.levelPercent(snapshot);
    final range = energy.rangeKm(snapshot);
    final status = energy.status?.call(snapshot) ?? const EnergyStatus();
    final levelText = level == null ? kNoValue : '$level%';
    final rangeText = range == null
        ? null
        : formatRange(range, data.units.distance);
    final power = status.powerWatts;

    final (
      String headline,
      String? detail,
      bool accent,
    ) = switch (status.flow) {
      EnergyFlow.idle => (
        [levelText, ?rangeText].join(' · '),
        tile.label,
        false,
      ),
      EnergyFlow.charging => (
        ['Charging', if (power != null) formatKilowatts(power)].join(' · '),
        _timeText(status),
        true,
      ),
      EnergyFlow.exporting => (
        ['Exporting', if (power != null) formatKilowatts(power)].join(' · '),
        levelText,
        true,
      ),
    };

    final spoken = [
      tile.accessibleLabel,
      if (level != null) '$level percent' else 'level unknown',
      ?rangeText,
      if (status.flow != EnergyFlow.idle) headline.toLowerCase(),
      if (status.flow == EnergyFlow.charging) ?detail,
      if (status.limitPercent case final limit?) 'limit $limit percent',
    ].join(', ');

    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: TileSurface(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      headline,
                      style: AppTextStyles.statValue.copyWith(
                        color: accent ? tokens.accent : null,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        detail,
                        style: TextStyle(color: tokens.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            _LevelBar(level: level, limit: status.limitPercent),
          ],
        ),
      ),
    );
  }

  static String? _timeText(EnergyStatus status) {
    final limit = status.limitPercent;
    final toLimit = status.timeToLimitMinutes;
    final to80 = status.timeTo80PercentMinutes;
    return [
      if (toLimit != null && toLimit > 0)
        '${formatMinutes(toLimit)} to ${limit != null ? '$limit%' : 'limit'}',
      if (to80 != null && to80 > 0 && limit != 80)
        '${formatMinutes(to80)} to 80%',
    ].join(' · ').nullIfEmpty;
  }
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// The level as a bar on the outline track, with a tick at the [limit].
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.level, required this.limit});

  final int? level;
  final int? limit;

  static const _height = 6.0;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final radius = BorderRadius.circular(_height / 2);
    return SizedBox(
      height: _height + 6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: _height,
                decoration: BoxDecoration(
                  color: tokens.outline,
                  borderRadius: radius,
                ),
              ),
              if (level case final level?)
                Container(
                  height: _height,
                  width: width * level.clamp(0, 100) / 100,
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    borderRadius: radius,
                  ),
                ),
              if (limit case final limit? when limit > 0 && limit < 100)
                Positioned(
                  left: width * limit / 100 - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: tokens.text),
                ),
            ],
          );
        },
      ),
    );
  }
}
