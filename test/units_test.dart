import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/cars/egmp/units.dart';
import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';

void main() {
  group('distances', () {
    test('range rounds like the cluster', () {
      expect(formatRange(336, DistanceUnit.kilometers), '336 km');
      expect(formatRange(336, DistanceUnit.miles), '209 mi');
    });

    test('odometer truncates like the cluster', () {
      expect(formatOdometer(22916, DistanceUnit.kilometers), '22916 km');
      expect(formatOdometer(22916, DistanceUnit.miles), '14239 mi');
    });

    test('speed', () {
      expect(formatSpeed(100, DistanceUnit.kilometers), '100 km/h');
      expect(formatSpeed(100, DistanceUnit.miles), '62 mph');
    });
  });

  group('temperatures', () {
    test('measured temperatures', () {
      expect(formatTemperature(19.5, TemperatureUnit.celsius), '19.5°C');
      expect(formatTemperature(19.5, TemperatureUnit.fahrenheit), '67°F');
    });

    test('the E-GMP target steps 1 °F per 0.5 °C', () {
      expect(formatEgmpClimateTarget(21, TemperatureUnit.celsius), '21.0°');
      expect(formatEgmpClimateTarget(17, TemperatureUnit.fahrenheit), '62°');
      expect(formatEgmpClimateTarget(17.5, TemperatureUnit.fahrenheit), '63°');
      expect(formatEgmpClimateTarget(27, TemperatureUnit.fahrenheit), '82°');
    });
  });

  test('durations', () {
    expect(formatMinutes(45), '45 min');
    expect(formatMinutes(65), '1 h 5 min');
  });

  test('E-GMP display units default to metric', () {
    final unknown = BasicState();
    expect(unknown.displayDistanceUnit, DistanceUnit.kilometers);
    expect(unknown.displayTemperatureUnit, TemperatureUnit.celsius);
    final imperial = BasicState(
      distanceUnit: BasicState_DistanceUnit.DISTANCE_UNIT_MILES,
      temperatureUnit: BasicState_TemperatureUnit.TEMPERATURE_UNIT_FAHRENHEIT,
    );
    expect(imperial.displayDistanceUnit, DistanceUnit.miles);
    expect(imperial.displayTemperatureUnit, TemperatureUnit.fahrenheit);
  });
}
