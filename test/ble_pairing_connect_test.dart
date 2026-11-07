import 'dart:async';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_car_app/providers/ble_pairing_connect.dart';

const _id = '00:11:22:33:44:55';

ConnectionStateUpdate _update(DeviceConnectionState state) =>
    ConnectionStateUpdate(deviceId: _id, connectionState: state, failure: null);

typedef _Attempt = void Function(StreamController<ConnectionStateUpdate> c);

/// Plays one scripted behaviour per `connectToDevice` call; the last one
/// repeats. Cancelling an attempt's stream counts as a disconnect.
class _ScriptedBle implements FlutterReactiveBle {
  _ScriptedBle(this.script);

  final List<_Attempt> script;
  int connectCalls = 0;
  int cancels = 0;

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) {
    final behaviour =
        script[connectCalls < script.length ? connectCalls : script.length - 1];
    connectCalls++;
    late final StreamController<ConnectionStateUpdate> controller;
    controller = StreamController<ConnectionStateUpdate>(
      onListen: () => behaviour(controller),
      onCancel: () => cancels++,
    );
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The attempt is refused: `connecting`, `disconnected`, end of stream.
void _refused(StreamController<ConnectionStateUpdate> c) {
  c.add(_update(DeviceConnectionState.connecting));
  c.add(_update(DeviceConnectionState.disconnected));
  unawaited(c.close());
}

void _connects(StreamController<ConnectionStateUpdate> c) {
  c.add(_update(DeviceConnectionState.connecting));
  c.add(_update(DeviceConnectionState.connected));
}

void _silent(StreamController<ConnectionStateUpdate> c) {}

Stream<ConnectionStateUpdate> _connect(
  _ScriptedBle ble, {
  Duration window = const Duration(seconds: 5),
}) => connectForPairing(
  ble,
  id: _id,
  window: window,
  attemptTimeout: const Duration(milliseconds: 100),
  retryDelay: const Duration(milliseconds: 10),
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  test('passes updates through when the first attempt connects', () async {
    final ble = _ScriptedBle([_connects]);
    final states = <DeviceConnectionState>[];
    final sub = _connect(ble).listen((u) => states.add(u.connectionState));
    await _settle();
    expect(states, [
      DeviceConnectionState.connecting,
      DeviceConnectionState.connected,
    ]);
    expect(ble.connectCalls, 1);
    await sub.cancel();
    expect(ble.cancels, 1);
  });

  test('retries an attempt that ends before connecting, hiding the '
      'disconnected updates', () async {
    final ble = _ScriptedBle([_refused, _refused, _connects]);
    final states = <DeviceConnectionState>[];
    final sub = _connect(ble).listen((u) => states.add(u.connectionState));
    await _settle();
    expect(ble.connectCalls, 3);
    expect(states, isNot(contains(DeviceConnectionState.disconnected)));
    expect(states.last, DeviceConnectionState.connected);
    await sub.cancel();
  });

  test('retries an attempt that errors before connecting', () async {
    final ble = _ScriptedBle([
      (c) => c.addError(Exception('refused')),
      _connects,
    ]);
    final states = <DeviceConnectionState>[];
    final errors = <Object>[];
    final sub = _connect(
      ble,
    ).listen((u) => states.add(u.connectionState), onError: errors.add);
    await _settle();
    expect(errors, isEmpty);
    expect(ble.connectCalls, 2);
    expect(states.last, DeviceConnectionState.connected);
    await sub.cancel();
  });

  test('cancels and restarts an attempt that stays silent', () async {
    final ble = _ScriptedBle([_silent, _connects]);
    final states = <DeviceConnectionState>[];
    final sub = _connect(ble).listen((u) => states.add(u.connectionState));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(ble.connectCalls, 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(ble.connectCalls, 2);
    // The silent attempt was cancelled, not left running.
    expect(ble.cancels, 1);
    expect(states.last, DeviceConnectionState.connected);
    await sub.cancel();
  });

  test('once connected, a drop is forwarded and not retried', () async {
    final ble = _ScriptedBle([
      (c) {
        _connects(c);
        c.add(_update(DeviceConnectionState.disconnected));
        unawaited(c.close());
      },
    ]);
    final states = <DeviceConnectionState>[];
    var done = false;
    _connect(
      ble,
    ).listen((u) => states.add(u.connectionState), onDone: () => done = true);
    await _settle();
    expect(states, [
      DeviceConnectionState.connecting,
      DeviceConnectionState.connected,
      DeviceConnectionState.disconnected,
    ]);
    expect(done, isTrue);
    expect(ble.connectCalls, 1);
  });

  test('once connected, errors are forwarded', () async {
    final ble = _ScriptedBle([
      (c) {
        _connects(c);
        c.addError(Exception('link lost'));
      },
    ]);
    final errors = <Object>[];
    final sub = _connect(ble).listen((_) {}, onError: errors.add);
    await _settle();
    expect(errors, hasLength(1));
    expect(ble.connectCalls, 1);
    await sub.cancel();
  });

  test('fails with a timeout once the window has passed', () async {
    final ble = _ScriptedBle([_refused]);
    final errors = <Object>[];
    var done = false;
    _connect(
      ble,
      window: const Duration(milliseconds: 100),
    ).listen((_) {}, onError: errors.add, onDone: () => done = true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(errors.single, isA<TimeoutException>());
    expect(done, isTrue);
    final calls = ble.connectCalls;
    expect(calls, greaterThan(1));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(ble.connectCalls, calls);
  });

  test('cancelling stops the retries', () async {
    final ble = _ScriptedBle([_refused]);
    final sub = _connect(ble).listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 35));
    await sub.cancel();
    final calls = ble.connectCalls;
    await _settle();
    expect(ble.connectCalls, calls);
  });
}
