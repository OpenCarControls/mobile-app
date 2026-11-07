import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';

/// The display units the car reports in its state. Unknown means metric.
extension EgmpUnits on BasicState {
  DistanceUnit get displayDistanceUnit =>
      distanceUnit == BasicState_DistanceUnit.DISTANCE_UNIT_MILES
      ? DistanceUnit.miles
      : DistanceUnit.kilometers;

  TemperatureUnit get displayTemperatureUnit =>
      temperatureUnit == BasicState_TemperatureUnit.TEMPERATURE_UNIT_FAHRENHEIT
      ? TemperatureUnit.fahrenheit
      : TemperatureUnit.celsius;
}

/// The climate target as the car shows it. In Fahrenheit the car steps 1 °F per
/// 0.5 °C (17 °C is 62 °F, 27 °C is 82 °F), so a plain conversion wouldn't
/// match its display.
String formatEgmpClimateTarget(double celsius, TemperatureUnit unit) =>
    switch (unit) {
      TemperatureUnit.celsius => '${celsius.toStringAsFixed(1)}°',
      TemperatureUnit.fahrenheit => '${((celsius - 14) * 2 + 56).round()}°',
    };
