import 'package:flutter/foundation.dart';

/// What the vehicle lists show of a vehicle without a live link: its last
/// known level, range and update.
@immutable
class VehicleSummary {
  const VehicleSummary({this.levelPercent, this.rangeKm, this.lastUpdated});

  final int? levelPercent;
  final int? rangeKm;
  final DateTime? lastUpdated;

  /// These fields, as stored in the vehicle's cached state.
  Map<String, dynamic> toCacheJson() => {
    if (levelPercent != null) 'levelPercent': levelPercent,
    if (rangeKm != null) 'rangeKm': rangeKm,
  };

  /// Reads them back from the cached state [json].
  factory VehicleSummary.fromCacheJson(Map<String, dynamic> json) =>
      VehicleSummary(
        levelPercent: json['levelPercent'] as int?,
        rangeKm: json['rangeKm'] as int?,
        lastUpdated: DateTime.tryParse((json['lastUpdated'] as String?) ?? ''),
      );
}
