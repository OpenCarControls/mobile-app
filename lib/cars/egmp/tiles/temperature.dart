import 'package:material_ui/material_ui.dart';

import 'package:open_car_app/cars/egmp/state_access.dart';
import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/tiles/state_tile.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

/// A temperature in the car's unit ("19.5 °C", "67 °F").
TileValue _value(double celsius, TemperatureUnit unit) => switch (unit) {
  TemperatureUnit.celsius => TileValue(celsius.toStringAsFixed(1), unit: '°C'),
  TemperatureUnit.fahrenheit => TileValue(
    celsiusToFahrenheit(celsius).round().toString(),
    unit: '°F',
  ),
};

TileValue? _inside(VehicleSnapshot s, TemperatureUnit unit) =>
    egmpBasic(s).hasIndoorTemperature()
    ? _value(egmpBasic(s).indoorTemperature, unit)
    : null;

TileValue? _outside(VehicleSnapshot s, TemperatureUnit unit) =>
    egmpBasic(s).hasOutdoorTemperature()
    ? _value(egmpBasic(s).outdoorTemperature, unit)
    : null;

/// The cabin and outside temperatures, side by side. Stands in for the
/// climate tile while the climate command isn't implemented.
final egmpTemperatureTile = CustomTileDefinition(
  id: 'temperature',
  label: 'Temperature',
  tier: TileTier.basic,
  sizes: const [TileSpan(2, 1)],
  describe: (data) {
    final unit = data.units.temperature;
    return 'inside ${_inside(data.snapshot, unit) ?? 'unknown'}, '
        'outside ${_outside(data.snapshot, unit) ?? 'unknown'}';
  },
  builder: (context, data) {
    final unit = data.units.temperature;
    return Row(
      children: [
        Expanded(
          child: _Reading(label: 'Inside', value: _inside(data.snapshot, unit)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Reading(
            label: 'Outside',
            value: _outside(data.snapshot, unit),
          ),
        ),
      ],
    );
  },
);

/// One temperature with its label above it.
class _Reading extends StatelessWidget {
  const _Reading({required this.label, required this.value});

  final String label;
  final TileValue? value;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: context.tokens.textSecondary)),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value?.value ?? kNoValue,
                  style: AppTextStyles.statValue,
                ),
                if (value?.unit case final unit?)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(fontSize: 13),
                  ),
              ],
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
