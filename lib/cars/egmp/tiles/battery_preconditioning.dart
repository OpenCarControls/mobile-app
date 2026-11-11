import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/cars/egmp/command_ids.dart';
import 'package:open_car_app/cars/egmp/state_access.dart';
import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/tiles/state_tile.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';
import 'package:open_car_app/widgets/tiles/tile_icon.dart';

typedef _Precond = AdvancedState_PreconditioningState;

/// Whether this device's manual preconditioning session is running.
bool _manual(VehicleSnapshot s) =>
    egmpAdvanced(s)?.isManualPreconditioningRequested ?? false;

/// Whether the car preconditions on its own (navigating to a DC charger):
/// the battery is preparing or heating and the session isn't ours.
bool _carsOwn(VehicleSnapshot s) {
  final a = egmpAdvanced(s);
  if (a == null || a.isManualPreconditioningRequested) return false;
  return a.preconditioningState == _Precond.PRECONDITIONING_STATE_PREPARING ||
      a.preconditioningState == _Precond.PRECONDITIONING_STATE_HEATING;
}

/// Preconditioning as the tile shows it, whoever started it. "Starting" covers
/// the time between our start and the car's first answer.
TileState egmpPreconditioningState(VehicleSnapshot s) {
  final a = egmpAdvanced(s);
  if (a == null || !a.hasPreconditioningState()) return kUnknownTileState;
  return switch (a.preconditioningState) {
    _Precond.PRECONDITIONING_STATE_HEATING => const TileState(
      on: true,
      caption: 'Enabled',
    ),
    _Precond.PRECONDITIONING_STATE_PREPARING => const TileState(
      on: true,
      caption: 'Starting',
    ),
    _ when a.isManualPreconditioningRequested => const TileState(
      on: true,
      caption: 'Starting',
    ),
    _ => const TileState(on: false, caption: 'Disabled'),
  };
}

/// The battery temperature in the car's unit: the average of the coldest and
/// warmest modules, rounded ("26 °C").
TileValue? egmpBatteryTemperature(VehicleSnapshot s, TemperatureUnit unit) {
  final a = egmpAdvanced(s);
  if (a == null ||
      !a.hasBatteryMinimumTemperature() ||
      !a.hasBatteryMaximumTemperature()) {
    return null;
  }
  final celsius =
      (a.batteryMinimumTemperature + a.batteryMaximumTemperature) / 2;
  return switch (unit) {
    TemperatureUnit.celsius => TileValue('${celsius.round()}', unit: '°C'),
    TemperatureUnit.fahrenheit => TileValue(
      '${celsiusToFahrenheit(celsius).round()}',
      unit: '°F',
    ),
  };
}

/// Why the command is greyed out, when the state tells.
String? _unavailableReason(VehicleSnapshot s) {
  if (_carsOwn(s)) return 'The car is preconditioning the battery on its own.';
  final power = egmpAdvanced(s)?.powerState;
  if (power != null &&
      power != AdvancedState_PowerState.POWER_STATE_UNSPECIFIED &&
      power != AdvancedState_PowerState.POWER_STATE_READY) {
    return 'The car needs to be in Ready.';
  }
  return null;
}

/// The battery temperature, with preconditioning under it. A tap starts or
/// stops the device's manual preconditioning; it is greyed out while the car
/// preconditions on its own.
final egmpBatteryPreconditioningTile = CommandTileDefinition(
  id: 'battery_preconditioning',
  label: 'Battery',
  accessibleLabel: 'Battery preconditioning',
  tier: TileTier.advanced,
  icon: const TileIcon.symbol(Symbols.heat),
  sizes: const [TileSpan(1, 1)],
  command: TileCommand(
    key: kBatteryPreconditioningCommand,
    build: (s) => AdvancedCommand(
      batteryPreconditioningCommand: BatteryPreconditioningCommand(
        enable: !_manual(s),
      ),
    ),
    activityName: (s) => _manual(s)
        ? 'Stop battery preconditioning'
        : 'Start battery preconditioning',
    unavailableReason: _unavailableReason,
  ),
  state: egmpPreconditioningState,
  content: (context, c) => _BatteryPreconditioningFace(
    temperature: egmpBatteryTemperature(c.snapshot, c.units.temperature),
    state: c.state,
    heating:
        egmpAdvanced(c.snapshot)?.preconditioningState ==
        _Precond.PRECONDITIONING_STATE_HEATING,
  ),
);

/// The temperature large in the centre, and the coil with the state under it.
class _BatteryPreconditioningFace extends StatelessWidget {
  const _BatteryPreconditioningFace({
    required this.temperature,
    required this.state,
    required this.heating,
  });

  final TileValue? temperature;
  final TileState state;

  /// Whether the battery heater is on.
  final bool heating;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: temperature?.value ?? kNoValue,
                    style: AppTextStyles.statValue.copyWith(fontSize: 24),
                  ),
                  if (temperature?.unit case final unit?)
                    TextSpan(
                      text: ' $unit',
                      style: const TextStyle(fontSize: 13),
                    ),
                ],
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Orange while the heater is on; "Starting" keeps the usual look.
                IconTheme.merge(
                  data: IconThemeData(
                    color: heating ? context.tokens.heat : null,
                  ),
                  child: TileIconView(
                    const TileIcon.symbol(Symbols.heat),
                    on: state.on,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  state.caption,
                  style: TextStyle(color: context.tokens.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
