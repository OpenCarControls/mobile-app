import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:protobuf/protobuf.dart';

import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/tiles/command_control.dart';
import 'package:open_car_app/widgets/tiles/state_tile.dart';
import 'package:open_car_app/widgets/tiles/tile_context.dart';
import 'package:open_car_app/widgets/tiles/tile_icon.dart';
import 'package:open_car_app/widgets/tiles/tile_surface.dart';

/// The Climate tile: a bar with the inside and outside temperatures and a power
/// button, and while climate is on, a panel with the target stepper and the
/// extras. The grid owner gives it [ClimateTileDefinition.onSpan] while on
/// ([TileDefinition.spanFor]).
///
/// Every button sends the same climate command, so only the one pressed
/// pulses; the temperatures stay.
class ClimateTile extends ConsumerWidget {
  const ClimateTile({super.key, required this.tile, required this.data});

  final ClimateTileDefinition tile;
  final TileContext data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final climate = tile.climate;
    final snapshot = data.snapshot;
    final unit = data.units.temperature;
    final on = climate.isOn(snapshot) ?? false;
    final send = ref.read(tileCommandSenderProvider);

    Future<Object?> sendMessage(GeneratedMessage message) =>
        send(climate.command, message);

    String temperature(double? celsius) =>
        celsius == null ? kNoValue : formatTemperature(celsius, unit);
    final temperatures =
        'Inside ${temperature(climate.insideCelsius(snapshot))} · '
        'Outside ${temperature(climate.outsideCelsius(snapshot))}';

    return TileSurface(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: SingleChildScrollView(
        // The panel is cut off while the tile grows, not laid out smaller.
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TileIconView(
                  tile.icon ?? const TileIcon.symbol(Symbols.thermostat),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    container: true,
                    label: '${tile.accessibleLabel}, $temperatures',
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tile.label, style: AppTextStyles.buttonTitle),
                        Text(
                          temperatures,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                _RoundButton(
                  id: '${tile.id}.power',
                  climate: climate,
                  icon: Symbols.power_settings_new,
                  label: '${tile.accessibleLabel}, ${on ? 'on' : 'off'}',
                  filled: on,
                  send: () => sendMessage(climate.power(snapshot, !on)),
                ),
              ],
            ),
            if (on) ...[
              const SizedBox(height: 12),
              _TargetStepper(
                id: tile.id,
                climate: climate,
                data: data,
                send: sendMessage,
              ),
              if (climate.extras.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  spacing: 8,
                  children: [
                    for (final extra in climate.extras)
                      Expanded(
                        child: _ExtraButton(
                          id: '${tile.id}.${extra.id}',
                          climate: climate,
                          extra: extra,
                          data: data,
                          send: sendMessage,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// − target +, in the car's own steps.
class _TargetStepper extends StatelessWidget {
  const _TargetStepper({
    required this.id,
    required this.climate,
    required this.data,
    required this.send,
  });

  final String id;
  final ClimateDescription climate;
  final TileContext data;
  final Future<Object?> Function(GeneratedMessage message) send;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final snapshot = data.snapshot;
    final target = climate.targetCelsius(snapshot);
    final shown = target == null
        ? kNoValue
        : climate.formatTarget(target, data.units.temperature);

    // Without a known target there is nothing to step from.
    Widget step(String suffix, IconData icon, String word, double delta) {
      final next = target == null ? null : target + delta;
      final allowed =
          next != null &&
          next >= climate.minCelsius - 1e-6 &&
          next <= climate.maxCelsius + 1e-6;
      final label = '$word, target $shown';
      if (!allowed) {
        return Semantics(
          button: true,
          enabled: false,
          label: label,
          excludeSemantics: true,
          child: SizedBox.square(
            dimension: kMinTouchTarget,
            child: Icon(icon, color: tokens.outline),
          ),
        );
      }
      return _RoundButton(
        id: '$id.target.$suffix',
        climate: climate,
        icon: icon,
        label: label,
        flat: true,
        send: () => send(climate.setTarget(snapshot, next)),
      );
    }

    return Container(
      decoration: ShapeDecoration(
        color: tokens.surface,
        shape: tokens.radiusPill.shape(side: BorderSide(color: tokens.outline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          step('down', Symbols.remove, 'Colder', -climate.stepCelsius),
          Expanded(
            child: Text(
              shown,
              textAlign: TextAlign.center,
              style: AppTextStyles.climateTarget,
            ),
          ),
          step('up', Symbols.add, 'Warmer', climate.stepCelsius),
        ],
      ),
    );
  }
}

/// A climate extra: its icon, filled while on, with level dots and a side tag
/// for a leveled one.
class _ExtraButton extends StatelessWidget {
  const _ExtraButton({
    required this.id,
    required this.climate,
    required this.extra,
    required this.data,
    required this.send,
  });

  final String id;
  final ClimateDescription climate;
  final ClimateExtra extra;
  final TileContext data;
  final Future<Object?> Function(GeneratedMessage message) send;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final snapshot = data.snapshot;
    final (
      bool on,
      int? level,
      String state,
      Future<Object?> Function() tap,
    ) = switch (extra) {
      ToggleClimateExtra(:final isOn, :final command) => () {
        final value = isOn(snapshot);
        return (
          value ?? false,
          null,
          value == null ? 'unknown' : (value ? 'on' : 'off'),
          () => send(command(snapshot, !(value ?? false))),
        );
      }(),
      LeveledClimateExtra(
        :final level,
        :final levels,
        :final next,
        :final command,
      ) =>
        () {
          final value = level(snapshot);
          return (
            (value ?? 0) > 0,
            value,
            value == null
                ? 'unknown'
                : value == 0
                ? 'off'
                : 'level $value of $levels',
            () => send(command(snapshot, next(value))),
          );
        }(),
    };
    final foreground = on ? tokens.onAccentContainer : tokens.text;
    final shape = tokens.radiusSmall.shape();
    final side = switch (extra.side) {
      ClimateSide.none => null,
      ClimateSide.left => 'L',
      ClimateSide.right => 'R',
    };

    return CommandControl(
      id: id,
      command: climate.command,
      send: tap,
      semanticLabel: '${extra.label}, $state',
      shape: shape,
      child: Container(
        height: 52,
        decoration: ShapeDecoration(
          color: on ? tokens.accentContainer : tokens.surface,
          shape: shape.copyWith(side: BorderSide(color: tokens.outline)),
        ),
        child: IconTheme.merge(
          data: IconThemeData(color: foreground),
          child: Stack(
            alignment: Alignment.center,
            children: [
              TileIconView(extra.icon, on: on),
              if (side != null)
                Positioned(
                  left: 6,
                  top: 3,
                  child: Text(
                    side,
                    style: AppTextStyles.buttonTitle.copyWith(
                      fontSize: 10,
                      color: foreground,
                    ),
                  ),
                ),
              if (extra case LeveledClimateExtra(:final levels))
                Positioned(
                  bottom: 5,
                  child: Row(
                    spacing: 3,
                    children: [
                      for (var i = 1; i <= levels; i++)
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i <= (level ?? 0)
                                ? foreground
                                : foreground.withValues(alpha: 0.3),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A circular button that sends the climate command.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.id,
    required this.climate,
    required this.icon,
    required this.label,
    required this.send,
    this.filled = false,
    this.flat = false,
  });

  final String id;
  final ClimateDescription climate;
  final IconData icon;
  final String label;
  final Future<Object?> Function() send;
  final bool filled;

  /// No fill or border, inside the stepper.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final shape = tokens.radiusRound.shape();
    return CommandControl(
      id: id,
      command: climate.command,
      send: send,
      semanticLabel: label,
      shape: shape,
      child: Container(
        width: kMinTouchTarget,
        height: kMinTouchTarget,
        decoration: flat
            ? null
            : ShapeDecoration(
                color: filled ? tokens.accent : tokens.surface,
                shape: shape.copyWith(side: BorderSide(color: tokens.outline)),
              ),
        child: Icon(icon, color: filled ? tokens.surface : tokens.text),
      ),
    );
  }
}
