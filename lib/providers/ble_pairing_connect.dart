import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

/// Connects to [id] for the pairing wizard, restarting the attempt for as long
/// as the link hasn't come up.
///
/// `FlutterReactiveBle.connectToDevice` does not retry by itself: its stream
/// ends at the first `disconnected` update, and cancelling it (which the
/// plugin does when the stream ends) tears the native attempt down. An attempt
/// can also end or go quiet right after it started (Android registers a GATT
/// client and closes it at once, mobile-app#52), which leaves a caller that
/// only waits for `connected` stuck until its own timeout. Here an attempt
/// that ends, fails or stays silent for [attemptTimeout] before `connected` is
/// cancelled, which makes the plugin disconnect the device and drop its native
/// connector, and a fresh one starts after [retryDelay]. Pre-connect
/// `disconnected` updates are not forwarded.
///
/// Once `connected` has been emitted the stream is the plugin's: updates,
/// errors and the end of the stream pass through unchanged and nothing is
/// retried. If the link hasn't come up within [window], the stream fails with
/// a [TimeoutException] and closes.
///
/// Cancelling the returned subscription cancels the current attempt.
Stream<ConnectionStateUpdate> connectForPairing(
  FlutterReactiveBle ble, {
  required String id,
  required Duration window,
  Duration attemptTimeout = const Duration(seconds: 15),
  // Longer than the plugin's 200 ms grace before it reports a disconnect it
  // was asked for, so that report can't land on the next attempt.
  Duration retryDelay = const Duration(milliseconds: 500),
}) {
  late final StreamController<ConnectionStateUpdate> out;
  StreamSubscription<ConnectionStateUpdate>? attempt;
  Timer? watchdog;
  Timer? retryTimer;
  final deadline = DateTime.now().add(window);
  var attempts = 0;
  var up = false;
  var stopped = false;

  void log(String message) =>
      dev.log('$message (attempt $attempts)', name: 'BlePairingConnect');

  void startAttempt() {
    retryTimer = null;
    if (stopped) return;
    if (!DateTime.now().isBefore(deadline)) {
      stopped = true;
      out.addError(
        TimeoutException('BLE link did not come up', window),
        StackTrace.current,
      );
      unawaited(out.close());
      return;
    }
    attempts++;

    void retry(String why) {
      if (stopped || up) return;
      log('Restarting: $why');
      watchdog?.cancel();
      final old = attempt;
      attempt = null;
      // Cancelling disconnects the device in the plugin.
      if (old != null) unawaited(old.cancel());
      retryTimer = Timer(retryDelay, startAttempt);
    }

    final thisAttempt = ble
        .connectToDevice(id: id, connectionTimeout: attemptTimeout)
        .listen(
          (update) {
            if (stopped) return;
            if (update.connectionState == DeviceConnectionState.connected) {
              up = true;
              watchdog?.cancel();
            } else if (!up &&
                update.connectionState == DeviceConnectionState.disconnected) {
              // The plugin ends the stream right after this; onDone retries.
              return;
            }
            out.add(update);
          },
          onError: (Object e, StackTrace s) {
            if (stopped) return;
            if (up) {
              out.addError(e, s);
            } else {
              retry('error before connected: $e');
            }
          },
          onDone: () {
            if (stopped) return;
            if (up) {
              stopped = true;
              unawaited(out.close());
            } else {
              retry('stream ended before connected');
            }
          },
        );
    attempt = thisAttempt;
    // The plugin's own timeout doesn't always fire.
    watchdog = Timer(attemptTimeout + attemptTimeout ~/ 10, () {
      if (identical(attempt, thisAttempt)) retry('no response');
    });
  }

  out = StreamController<ConnectionStateUpdate>(
    onListen: startAttempt,
    onCancel: () async {
      stopped = true;
      watchdog?.cancel();
      retryTimer?.cancel();
      await attempt?.cancel();
      attempt = null;
    },
  );
  return out.stream;
}
