import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_car_app/config/connection_activity_config.dart';
import 'package:open_car_app/models/connection_activity.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';

/// Holds the logs loaded before [runApp]. Overridden in [ProviderScope] at app
/// startup; never reads storage itself.
final initialConnectionActivityProvider = Provider<ConnectionActivityLogs>(
  (_) => const {},
);

/// What this phone saw and did with each vehicle. Local to the phone: it is
/// not synced with the vehicle or other phones.
class ConnectionActivityNotifier extends Notifier<ConnectionActivityLogs> {
  /// The clock, replaceable in tests.
  DateTime Function() now = DateTime.now;

  /// Writes run one at a time, so an older list can't replace a newer one and
  /// a late save can't bring back a deleted log.
  Future<void> _lastWrite = Future.value();

  Future<void> _write(Future<void> Function() write) =>
      _lastWrite = _lastWrite.then((_) => write(), onError: (_) => write());

  @override
  ConnectionActivityLogs build() => ref.read(initialConnectionActivityProvider);

  void recordConnection(ConnectionChange change) =>
      _add((time) => ConnectionChangeEntry(time, change));

  /// Records what came of [command]. A new [CommandOutcome] is all a further
  /// result needs, like a command left unknown by a transport change (#23).
  void recordCommand(
    String command,
    CommandOutcome outcome, {
    bool sentRemotely = false,
  }) => _add(
    (time) => CommandEntry(
      time,
      command: command,
      outcome: outcome,
      sentRemotely: sentRemotely,
    ),
  );

  /// Deletes the log of an unpaired vehicle.
  Future<void> forget(String vehicleKey) async {
    state = {...state}..remove(vehicleKey);
    await _write(() => clearConnectionActivity(vehicleKey));
  }

  void _add(ConnectionActivityEntry Function(DateTime time) entry) {
    final vehicleKey = ref.read(pairedVehicleProvider)?.storageKey;
    if (vehicleKey == null) return;
    final entries = [
      entry(now()),
      ...?state[vehicleKey],
    ].take(kConnectionActivityMaxEntries).toList();
    state = {...state, vehicleKey: entries};
    unawaited(_write(() => saveConnectionActivity(vehicleKey, entries)));
  }
}

final connectionActivityLogsProvider =
    NotifierProvider<ConnectionActivityNotifier, ConnectionActivityLogs>(
      ConnectionActivityNotifier.new,
    );

/// Records the current vehicle's connection changes. Listened to for as long
/// as the app runs.
///
/// Remote counts as connected once the vehicle answers, not when the broker
/// is reached, so the log agrees with the connection pill. Going live over
/// MQTT always follows a transport change or a silence from the vehicle:
/// [VehicleStateNotifier] resets the liveness on every transport change.
final connectionActivityRecorderProvider = Provider<void>((ref) {
  if (ref.watch(selectedVehicleProvider) == null) return;
  final log = ref.read(connectionActivityLogsProvider.notifier);

  ref.listen(transportTypeProvider, (previous, next) {
    if (next == TransportType.ble) {
      log.recordConnection(ConnectionChange.bluetoothConnected);
    } else if (previous == TransportType.ble && next == TransportType.mqtt) {
      log.recordConnection(ConnectionChange.bluetoothLost);
    }
  });

  ref.listen(vehicleStateProvider.select((s) => s.isStateLive), (_, live) {
    if (live && ref.read(transportTypeProvider) == TransportType.mqtt) {
      log.recordConnection(ConnectionChange.remoteConnected);
    }
  });
});

/// The current vehicle's log, newest first.
final connectionActivityProvider = Provider<List<ConnectionActivityEntry>>((
  ref,
) {
  final vehicleKey = ref.watch(pairedVehicleProvider)?.storageKey;
  if (vehicleKey == null) return const [];
  return ref.watch(connectionActivityLogsProvider)[vehicleKey] ?? const [];
});
