/// Formatting of distances, speeds, temperatures and durations in the units the
/// car displays. Vehicle states carry kilometres, km/h and degrees Celsius; each
/// platform reads the car's display units from its own state.
library;

/// The unit a car displays distances and speeds in.
enum DistanceUnit { kilometers, miles }

/// The unit a car displays temperatures in.
enum TemperatureUnit { celsius, fahrenheit }

const double kKmPerMile = 1.609344;

/// A range, rounded like the cluster rounds it (336 km is 209 mi).
String formatRange(int km, DistanceUnit unit) => switch (unit) {
  DistanceUnit.kilometers => '$km km',
  DistanceUnit.miles => '${(km / kKmPerMile).round()} mi',
};

/// An odometer reading, truncated like the cluster truncates it (22916 km is
/// 14239 mi).
String formatOdometer(int km, DistanceUnit unit) => switch (unit) {
  DistanceUnit.kilometers => '$km km',
  DistanceUnit.miles => '${(km / kKmPerMile).floor()} mi',
};

/// A speed. It arrives in whole km/h, so it can be 1 mph off the cluster.
String formatSpeed(int kmh, DistanceUnit unit) => switch (unit) {
  DistanceUnit.kilometers => '$kmh km/h',
  DistanceUnit.miles => '${(kmh / kKmPerMile).round()} mph',
};

/// Converts degrees Celsius to Fahrenheit.
double celsiusToFahrenheit(double celsius) => celsius * 9 / 5 + 32;

/// A measured temperature (inside, outside), with its unit.
String formatTemperature(double celsius, TemperatureUnit unit) =>
    switch (unit) {
      TemperatureUnit.celsius => '${celsius.toStringAsFixed(1)}°C',
      TemperatureUnit.fahrenheit => '${celsiusToFahrenheit(celsius).round()}°F',
    };

/// A duration in minutes, as `45 min` or `1 h 5 min`.
String formatMinutes(int minutes) =>
    minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min';

/// A power in kW with one decimal ("7.2 kW").
String formatKilowatts(int watts) => '${(watts / 1000).toStringAsFixed(1)} kW';
