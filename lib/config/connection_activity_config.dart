import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/models/connection_activity.dart';

const _kPrefsPrefix = 'connection_activity/';

/// Each vehicle's connection activity, newest first, by the vehicle's storage
/// key.
typedef ConnectionActivityLogs = Map<String, List<ConnectionActivityEntry>>;

/// Loads every vehicle's log. An entry that can't be read is skipped. Call
/// once at app startup, before [runApp].
Future<ConnectionActivityLogs> loadConnectionActivity() async {
  final prefs = await SharedPreferences.getInstance();
  final logs = <String, List<ConnectionActivityEntry>>{};
  for (final key in prefs.getKeys()) {
    if (!key.startsWith(_kPrefsPrefix)) continue;
    final raw = prefs.getString(key);
    if (raw == null) continue;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      continue;
    }
    if (decoded is! List) continue;
    logs[key.substring(_kPrefsPrefix.length)] = [
      for (final json in decoded) ?_entryFromJson(json),
    ];
  }
  return logs;
}

Future<void> saveConnectionActivity(
  String vehicleKey,
  List<ConnectionActivityEntry> entries,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    '$_kPrefsPrefix$vehicleKey',
    jsonEncode([for (final entry in entries) _entryToJson(entry)]),
  );
}

Future<void> clearConnectionActivity(String vehicleKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('$_kPrefsPrefix$vehicleKey');
}

Map<String, Object> _entryToJson(ConnectionActivityEntry entry) => {
  'time': entry.time.toUtc().toIso8601String(),
  ...switch (entry) {
    ConnectionChangeEntry(:final change) => {'change': change.name},
    CommandEntry(:final command, :final outcome, :final sentRemotely) => {
      'command': command,
      'outcome': outcome.name,
      'sentRemotely': sentRemotely,
    },
  },
};

ConnectionActivityEntry? _entryFromJson(Object? raw) {
  try {
    final json = raw as Map<String, dynamic>;
    final time = DateTime.parse(json['time'] as String).toLocal();
    final change = json['change'] as String?;
    if (change != null) {
      return ConnectionChangeEntry(
        time,
        ConnectionChange.values.byName(change),
      );
    }
    return CommandEntry(
      time,
      command: json['command'] as String,
      outcome: CommandOutcome.values.byName(json['outcome'] as String),
      sentRemotely: json['sentRemotely'] as bool,
    );
  } catch (_) {
    return null;
  }
}
