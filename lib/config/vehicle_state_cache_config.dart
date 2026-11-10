import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/models/vehicle_summary.dart';

/// The last known state of each vehicle is stored under this prefix plus the
/// vehicle's storage key.
const kVehicleStateCachePrefix = 'vehicle_state_';

/// Loads every vehicle's last known summary, by storage key. A corrupt entry is
/// skipped. Call once at app startup, before [runApp].
Future<Map<String, VehicleSummary>> loadVehicleSummaries() async {
  final prefs = await SharedPreferences.getInstance();
  final summaries = <String, VehicleSummary>{};
  for (final key in prefs.getKeys()) {
    if (!key.startsWith(kVehicleStateCachePrefix)) continue;
    final raw = prefs.getString(key);
    if (raw == null) continue;
    try {
      summaries[key.substring(kVehicleStateCachePrefix.length)] =
          VehicleSummary.fromCacheJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt data: this vehicle shows no summary until its next update.
    }
  }
  return summaries;
}

Future<void> clearVehicleStateCache(String vehicleKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('$kVehicleStateCachePrefix$vehicleKey');
}
