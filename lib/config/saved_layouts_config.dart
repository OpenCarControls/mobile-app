import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/models/dashboard_layout.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

const _kPrefsPrefix = 'dashboard_layout/';

/// The user's layouts by [savedLayoutKey].
typedef SavedLayouts = Map<String, List<TileLayoutEntry>>;

/// The key of [grid]'s layout on the vehicle with [vehicleKey].
String savedLayoutKey(String vehicleKey, DashboardGrid grid) =>
    '$vehicleKey/${grid.name}';

/// Loads every saved layout, as stored: whether a tile still exists depends on
/// the vehicle ([sanitizeLayout]). A corrupt one is skipped, so its grid falls
/// back to the default. Call once at app startup, before [runApp].
Future<SavedLayouts> loadSavedLayouts() async {
  final prefs = await SharedPreferences.getInstance();
  final layouts = <String, List<TileLayoutEntry>>{};
  for (final key in prefs.getKeys()) {
    if (!key.startsWith(_kPrefsPrefix)) continue;
    final raw = prefs.getString(key);
    if (raw == null) continue;
    try {
      layouts[key.substring(_kPrefsPrefix.length)] = [
        for (final entry in jsonDecode(raw) as List)
          _entryFromJson(entry as Map<String, dynamic>),
      ];
    } catch (_) {
      // Corrupt data: the grid shows its default.
    }
  }
  return layouts;
}

Future<void> saveLayout(String key, List<TileLayoutEntry> layout) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    '$_kPrefsPrefix$key',
    jsonEncode([
      for (final entry in layout)
        {
          'id': entry.tileId,
          'columns': entry.span.columns,
          'rows': entry.span.rows,
        },
    ]),
  );
}

Future<void> clearLayout(String key) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('$_kPrefsPrefix$key');
}

TileLayoutEntry _entryFromJson(Map<String, dynamic> json) {
  final columns = json['columns'] as int;
  final rows = json['rows'] as int;
  if (columns <= 0 || rows <= 0) throw const FormatException('Bad tile span');
  return (tileId: json['id'] as String, span: TileSpan(columns, rows));
}
