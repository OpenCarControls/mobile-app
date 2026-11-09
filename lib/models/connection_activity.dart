/// How many entries the connection activity keeps per vehicle.
const kConnectionActivityMaxEntries = 200;

/// A change in how the phone reaches the vehicle.
enum ConnectionChange { bluetoothConnected, bluetoothLost, remoteConnected }

/// What came of a command the user sent, in the log's fixed plain words. Raw
/// device or transport messages are never logged.
enum CommandOutcome {
  done('Done'),
  noAnswer('No answer from the vehicle'),
  vehicleUnavailable('Vehicle unavailable'),
  needsApproval('Needs approval'),
  notValidated('Phone not validated'),
  failed('Failed');

  const CommandOutcome(this.text);

  final String text;
}

/// One line of the connection activity: what this phone saw and did. Nothing
/// here identifies the device, the phone or the broker, because the log can
/// be shared.
sealed class ConnectionActivityEntry {
  const ConnectionActivityEntry(this.time);

  final DateTime time;

  String get title;

  String? get detail;

  /// Whether the detail line reports a failure.
  bool get isFailure;
}

final class ConnectionChangeEntry extends ConnectionActivityEntry {
  const ConnectionChangeEntry(super.time, this.change);

  final ConnectionChange change;

  @override
  String get title => switch (change) {
    ConnectionChange.bluetoothConnected => 'Bluetooth connected',
    ConnectionChange.bluetoothLost => 'Bluetooth link lost',
    ConnectionChange.remoteConnected => 'Remote connected',
  };

  @override
  String? get detail => switch (change) {
    ConnectionChange.bluetoothLost => 'Switched to remote',
    _ => null,
  };

  @override
  bool get isFailure => false;
}

final class CommandEntry extends ConnectionActivityEntry {
  const CommandEntry(
    super.time, {
    required this.command,
    required this.outcome,
    this.sentRemotely = false,
  });

  /// The command's name as the user knows it, like "Unlock doors".
  final String command;

  final CommandOutcome outcome;

  final bool sentRemotely;

  @override
  String get title => command;

  @override
  String get detail =>
      [outcome.text, if (sentRemotely) 'sent remotely'].join(' · ');

  @override
  bool get isFailure => outcome != CommandOutcome.done;
}
