import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kPrefsKey = 'theme_mode';

/// Loads the saved theme mode. Falls back to following the system when
/// nothing valid is saved.
///
/// Call once at app startup (before [runApp]), so the first frame already has
/// the right brightness.
Future<ThemeMode> loadThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_kPrefsKey);
  return ThemeMode.values.asNameMap()[saved] ?? ThemeMode.system;
}

Future<void> saveThemeMode(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kPrefsKey, mode.name);
}
