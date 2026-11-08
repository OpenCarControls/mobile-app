import 'package:shared_preferences/shared_preferences.dart';

const _kPrefsKey = 'dashboard_button_style';

/// How the dashboard's command tiles look.
enum DashboardButtonStyle { titled, iconOnly }

/// Loads the saved button style. Call once at app startup, before [runApp].
Future<DashboardButtonStyle> loadButtonStyle() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_kPrefsKey);
  return DashboardButtonStyle.values.asNameMap()[saved] ??
      DashboardButtonStyle.titled;
}

Future<void> saveButtonStyle(DashboardButtonStyle style) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kPrefsKey, style.name);
}
