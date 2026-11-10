import 'package:shared_preferences/shared_preferences.dart';

const _kPrefsPrefix = 'unsupported_commands/';

/// The commands each vehicle doesn't have, by the vehicle's storage key.
typedef UnsupportedCommands = Map<String, Set<String>>;

/// Loads what was remembered of every vehicle. Call once at app startup,
/// before [runApp].
Future<UnsupportedCommands> loadUnsupportedCommands() async {
  final prefs = await SharedPreferences.getInstance();
  return {
    for (final key in prefs.getKeys())
      if (key.startsWith(_kPrefsPrefix))
        key.substring(_kPrefsPrefix.length): {...?prefs.getStringList(key)},
  };
}

Future<void> clearUnsupportedCommands(String vehicleKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('$_kPrefsPrefix$vehicleKey');
}

Future<void> saveUnsupportedCommands(
  String vehicleKey,
  Set<String> commands,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('$_kPrefsPrefix$vehicleKey', commands.toList());
}
