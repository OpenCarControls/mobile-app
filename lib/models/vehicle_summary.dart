import 'package:flutter/foundation.dart';

import 'package:open_car_app/formatting/units.dart';

/// What the vehicle lists show of a vehicle without a live link: its last
/// known level, range and update.
@immutable
class VehicleSummary {
  const VehicleSummary({
    this.levelPercent,
    this.rangeKm,
    this.distanceUnit,
    this.lastUpdated,
  });

  final int? levelPercent;
  final int? rangeKm;

  /// The unit the car displayed distances in; null before it was known.
  final DistanceUnit? distanceUnit;
  final DateTime? lastUpdated;

  /// These fields, as stored in the vehicle's cached state.
  Map<String, dynamic> toCacheJson() => {
    if (levelPercent != null) 'levelPercent': levelPercent,
    if (rangeKm != null) 'rangeKm': rangeKm,
    if (distanceUnit != null) 'distanceUnit': distanceUnit!.name,
  };

  /// Reads them back from the cached state [json].
  factory VehicleSummary.fromCacheJson(Map<String, dynamic> json) =>
      VehicleSummary(
        levelPercent: json['levelPercent'] as int?,
        rangeKm: json['rangeKm'] as int?,
        distanceUnit: DistanceUnit.values.asNameMap()[json['distanceUnit']],
        lastUpdated: DateTime.tryParse((json['lastUpdated'] as String?) ?? ''),
      );
}
