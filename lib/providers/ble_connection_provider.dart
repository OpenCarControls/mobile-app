import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Transport constants are identical in every vehicle's constants.g.dart.
import 'package:open_car_app/cars/virtual_car/constants.g.dart'
    show kBleAttMtu, kBleMinAttMtu;
import 'package:open_car_app/providers/ble_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// ── Connection state ──────────────────────────────────────────────────────────

/// Represents the current state of the BLE connection lifecycle.
sealed class BleConnectionState {
  const BleConnectionState();
}

/// Scanning for the car's BLE service advertisement.
/// Emitted only by [PairingWizardScreen] during the pairing flow; not emitted
/// by [BleConnectionNotifier] after a device is already paired.
class BleScanning extends BleConnectionState {
  const BleScanning();
}

/// Establishing BLE connection — connecting to the known device and
/// initialising characteristics. MQTT remains the active transport.
class BleConnecting extends BleConnectionState {
  final String deviceId;
  const BleConnecting(this.deviceId);
}

/// Connected to the car over BLE and fully ready for communication:
/// services discovered, required characteristics resolved, notifications
/// enabled. The transport provider switches to BLE on this state.
class BleReady extends BleConnectionState {
  final String deviceId;

  /// ATT MTU negotiated for this connection; sizes the outgoing BLE chunks.
  final int attMtu;
  const BleReady(this.deviceId, {required this.attMtu});
}

/// Not connected and not attempting to connect (BLE unavailable, disabled,
/// no paired device, or device paired via HTTP transport).
/// [warning] carries a human-readable reason when set.
class BleDisconnected extends BleConnectionState {
  final String? warning;
  const BleDisconnected({this.warning});
}

/// The connected device doesn't look like the paired car (service or
/// characteristics missing). Thrown from the post-connect setup.
class _BleSetupException implements Exception {
  final String message;
  const _BleSetupException(this.message);

  @override
  String toString() => message;
}

/// The link can't be used: the MTU exchange failed or gave less than the
/// contract needs (Android reports 0 when the link dropped meanwhile).
class _BleLinkException implements Exception {
  final String message;
  const _BleLinkException(this.message);

  @override
  String toString() => message;
}

// ── Lost bond detection ───────────────────────────────────────────────────────

/// A link that drops this soon after connecting counts as an early drop.
const _kEarlyDropWindow = Duration(seconds: 10);

/// An attempt that fails this soon, without Android ever reporting
/// `connected`, also counts: with its pairing window closed the firmware hangs
/// up on an unknown phone within milliseconds. An out-of-range attempt only
/// fails at the 30 s connection timeout.
const _kRefusedConnectWindow = Duration(seconds: 5);

/// Early drops in a row after which the device probably no longer has this
/// phone's bond.
const _kEarlyDropsForLostBond = 2;

/// Whether the device keeps dropping the link right after connecting, which
/// means it most likely no longer knows this phone (its bond was removed, or
/// its flash erased) while Android still has the old keys. Android shows no
/// pairing prompt then, so the app has to tell the user. Cleared by a link
/// that stays up, and on unpair.
class BleBondLostNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(pairedVehicleProvider);
    return false;
  }

  void report(bool lost) {
    if (state != lost) state = lost;
  }
}

final bleBondLostProvider = NotifierProvider<BleBondLostNotifier, bool>(
  BleBondLostNotifier.new,
);

// ── Notifier ──────────────────────────────────────────────────────────────────

class BleConnectionNotifier extends Notifier<BleConnectionState> {
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<BleStatus>? _statusSubscription;
  bool _connecting = false;
  bool _disposed = false;
  // Pending retry after the connection stream ends. Only one may be scheduled,
  // and any new connection attempt cancels it.
  Timer? _retryTimer;
  // Bumped whenever a link comes up or goes away (connected, disconnected,
  // stream end, cancel). Post-connect setup belongs to the link that was up
  // when it started, and gives up as soon as this moves on.
  int _linkGeneration = 0;
  // Running while a drop of the current attempt or link counts as early.
  Timer? _earlyDropTimer;
  int _earlyDrops = 0;

  @override
  BleConnectionState build() {
    final config = ref.watch(pairedVehicleProvider);

    // No paired device, or user prefers HTTP — BLE not needed.
    if (config == null || !config.usesBle) {
      return const BleDisconnected();
    }

    _disposed = false;
    ref.onDispose(_cleanup);
    unawaited(_initConnection(config.bleRemoteId));
    return BleConnecting(config.bleRemoteId);
  }

  Future<void> _initConnection(String remoteId) async {
    final granted = await _requestPermissions();
    // Riverpod 3 throws when a disposed Ref is used after an await.
    if (!ref.mounted) return;
    if (!granted) {
      dev.log('Bluetooth permission denied', name: 'BleConnection');
      state = const BleDisconnected(
        warning: 'Bluetooth permission denied. Grant it in app settings.',
      );
      return;
    }

    final ble = ref.read(bleProvider);

    // Watch adapter status — connect when ready, warn when off.
    _statusSubscription = ble.statusStream.listen((status) {
      dev.log('BLE status: $status', name: 'BleConnection');
      switch (status) {
        case BleStatus.ready:
          _connectDirectly(remoteId);
        case BleStatus.poweredOff:
          _cancelConnection();
          state = const BleDisconnected(warning: 'Bluetooth is off.');
        case BleStatus.unauthorized:
          _cancelConnection();
          state = const BleDisconnected(
            warning: 'Bluetooth permission denied. Grant it in app settings.',
          );
        default:
          break;
      }
    });
  }

  Future<bool> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  /// Starts the window in which a drop counts as early: [_kRefusedConnectWindow]
  /// from the start of an attempt, then [_kEarlyDropWindow] once the link is
  /// up. A link that outlives its window resets the count; an attempt that is
  /// still connecting (out of range) doesn't.
  void _startEarlyDropWindow({required bool linkUp}) {
    _earlyDropTimer?.cancel();
    _earlyDropTimer = Timer(
      linkUp ? _kEarlyDropWindow : _kRefusedConnectWindow,
      () {
        _earlyDropTimer = null;
        if (!linkUp) return;
        _earlyDrops = 0;
        ref.read(bleBondLostProvider.notifier).report(false);
      },
    );
  }

  /// The attempt failed or the link went down (or post-connect setup failed
  /// because it did). Counted once per attempt or link.
  void _onLinkDropped() {
    if (_earlyDropTimer?.isActive != true) return;
    _earlyDropTimer!.cancel();
    _earlyDropTimer = null;
    _earlyDrops++;
    dev.log(
      'Link dropped right after connecting ($_earlyDrops in a row)',
      name: 'BleConnection',
    );
    if (_earlyDrops >= _kEarlyDropsForLostBond) {
      ref.read(bleBondLostProvider.notifier).report(true);
    }
  }

  void _cancelConnection() {
    // A drop we cause ourselves says nothing about the bond.
    _earlyDropTimer?.cancel();
    _earlyDropTimer = null;
    _linkGeneration++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connecting = false;
  }

  void _connectDirectly(String remoteId) {
    if (_connecting || state is BleReady) return;
    _connecting = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    // Drop any previous connection stream so it can't leak or emit into this one.
    _connectionSubscription?.cancel();
    state = BleConnecting(remoteId);
    _startEarlyDropWindow(linkUp: false);

    final ble = ref.read(bleProvider);
    dev.log('Connecting to $remoteId', name: 'BleConnection');

    // connectToDevice emits updates for the lifetime of the subscription and
    // automatically retries when the device is out of range. Only when the
    // stream itself ends does `_scheduleRetry` start a new one.
    _connectionSubscription = ble
        .connectToDevice(
          id: remoteId,
          connectionTimeout: const Duration(seconds: 30),
        )
        .listen(
          (update) => _onConnectionUpdate(update, remoteId),
          onError: (Object e) {
            dev.log('Connection stream error: $e', name: 'BleConnection');
            _onLinkDropped();
            _linkGeneration++;
            _connecting = false;
            state = BleConnecting(remoteId);
            _scheduleRetry(remoteId);
          },
          onDone: () {
            dev.log('Connection stream done', name: 'BleConnection');
            _onLinkDropped();
            _linkGeneration++;
            _connecting = false;
            state = BleConnecting(remoteId);
            _scheduleRetry(remoteId);
          },
        );
  }

  void _scheduleRetry(String remoteId) {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 30), () {
      _retryTimer = null;
      if (!_disposed) _connectDirectly(remoteId);
    });
  }

  void forceReconnect() {
    if (_disposed) return;
    if (state is BleReady) {
      dev.log(
        'Already connected, ignoring force reconnect',
        name: 'BleConnection',
      );
      return;
    }

    final config = ref.read(pairedVehicleProvider);
    if (config == null || !config.usesBle) return;
    dev.log('Force reconnect requested', name: 'BleConnection');
    _cancelConnection();
    _connectDirectly(config.bleRemoteId);
  }

  /// Pull-to-refresh on a dashboard: reconnects BLE now, cancelling the
  /// pending retry. Decided from the paired vehicle's config, not the current
  /// transport, which stays MQTT until BLE is ready (the only time a manual
  /// retry helps). Nothing to do while connected.
  Future<void> pullToRefresh() async {
    final config = ref.read(pairedVehicleProvider);
    if (config == null || !config.usesBle) return;
    // Bluetooth off or permission denied: the adapter status stream connects
    // once that's fixed, and a pull can't help meanwhile.
    if (state is BleDisconnected) return;
    forceReconnect();
    // A short delay so the refresh indicator shows.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  Future<void> _onConnectionUpdate(
    ConnectionStateUpdate update,
    String remoteId,
  ) async {
    dev.log(
      'Connection update: ${update.connectionState}',
      name: 'BleConnection',
    );
    switch (update.connectionState) {
      case DeviceConnectionState.connected:
        _startEarlyDropWindow(linkUp: true);
        await _onConnected(remoteId, ++_linkGeneration);
      case DeviceConnectionState.disconnected:
        dev.log('Disconnected from $remoteId', name: 'BleConnection');
        _onLinkDropped();
        _linkGeneration++;
        _connecting = false;
        // connectToDevice will reconnect automatically while the subscription
        // lives — just reset to connecting state.
        state = BleConnecting(remoteId);
      default:
        break;
    }
  }

  Future<void> _onConnected(String remoteId, int generation) async {
    final ble = ref.read(bleProvider);

    // True once the link this setup started on has dropped, been cancelled
    // (including by pull-to-refresh) or been replaced. The handler that moved
    // the generation on already set the state and scheduled what comes next,
    // so a stale setup just stops: going on would call `discoverAllServices`
    // on a dead link, which makes Android reconnect outside the
    // `connectToDevice` stream, and then report `BleReady` over that state.
    bool stale() {
      if (ref.mounted && generation == _linkGeneration) return false;
      dev.log(
        'Link to $remoteId changed during setup; abandoning it',
        name: 'BleConnection',
      );
      return true;
    }

    try {
      // Negotiate MTU before emitting BleReady. Messages are split into
      // chunks sized from it, so a smaller MTU only means more chunks, down to
      // kBleMinAttMtu: below that the device can't send its largest messages
      // and drops them, so the link is no use.
      final mtu = await ble.requestMtu(deviceId: remoteId, mtu: kBleAttMtu);
      if (stale()) return;
      if (mtu < kBleMinAttMtu) {
        throw _BleLinkException(
          'MTU $mtu negotiated for $remoteId, below the $kBleMinAttMtu BLE '
          'needs',
        );
      } else if (mtu < kBleAttMtu) {
        dev.log(
          'MTU $mtu negotiated for $remoteId, below the $kBleAttMtu '
          'requested; messages will use smaller chunks',
          name: 'BleConnection',
        );
      } else {
        dev.log('MTU $mtu negotiated for $remoteId', name: 'BleConnection');
      }

      // Clear Android's cached GATT profile before service discovery.
      // On bonded devices Android reuses the cached profile from the previous
      // connection, which returns the characteristic's descriptors list as
      // empty. flutter_reactive_ble then falls back to COMPAT notification
      // mode (setCharacteristicNotification only, no CCCD write), so the
      // firmware never receives the [0x01, 0x00] that enables notifications.
      // Clearing the cache forces a fresh over-the-air discovery that includes
      // the CCCD descriptor, restoring DEFAULT mode and working notifications.
      try {
        await ble.clearGattCache(remoteId);
        dev.log('GATT cache cleared for $remoteId', name: 'BleConnection');
      } on Exception catch (e) {
        // Non-fatal: some Android versions don't expose the hidden refresh()
        // API. Log and continue — notifications may not work on those devices.
        dev.log('clearGattCache failed (non-fatal): $e', name: 'BleConnection');
      }
      if (stale()) return;

      // Discover services and characteristics.
      await ble.discoverAllServices(remoteId);
      if (stale()) return;
      dev.log('Services discovered for $remoteId', name: 'BleConnection');

      // Verify the required characteristics are present.
      final vehicle = ref.read(selectedVehicleProvider);
      if (vehicle == null) {
        dev.log('No vehicle selected — cannot verify characteristics');
        state = const BleDisconnected();
        _connecting = false;
        return;
      }

      final services = await ble.getDiscoveredServices(remoteId);
      if (stale()) return;
      final serviceUuid = Uuid.parse(vehicle.bleServiceUuid);
      final serviceMatch = services.where((s) => s.id == serviceUuid);
      if (serviceMatch.isEmpty) {
        throw _BleSetupException(
          'BLE service ${vehicle.bleServiceUuid} not found on $remoteId',
        );
      }
      final chars = serviceMatch.first.characteristics;
      final charIds = chars.map((c) => c.id.toString().toLowerCase()).toSet();
      final needed = {
        vehicle.bleAppToDeviceCharacteristicUuid.toLowerCase(),
        vehicle.bleDeviceToAppCharacteristicUuid.toLowerCase(),
      };
      if (!charIds.containsAll(needed)) {
        throw _BleSetupException(
          'Required BLE characteristics not found in service '
          '${vehicle.bleServiceUuid}',
        );
      }

      dev.log('BLE ready: $remoteId', name: 'BleConnection');
      state = BleReady(remoteId, attMtu: mtu);
      _connecting = false;
    } on Exception catch (e) {
      dev.log('Post-connect init failed: $e', name: 'BleConnection');
      // Usually the link dropping under the setup; then it's already handled
      // (and counted).
      if (stale()) return;
      // An unusable MTU usually means the device dropped the link; a missing
      // service is a wrong device, not a lost bond.
      if (e is! _BleSetupException) _onLinkDropped();
      // The link is still up, so connectToDevice won't emit `connected` again
      // and nothing else would retry. Drop the connection (cancelling the
      // stream disconnects) and start over after the usual delay.
      _cancelConnection();
      state = BleConnecting(remoteId);
      _scheduleRetry(remoteId);
    }
  }

  void _cleanup() {
    _disposed = true;
    _earlyDropTimer?.cancel();
    _earlyDropTimer = null;
    _linkGeneration++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _statusSubscription?.cancel();
    _statusSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connecting = false;
  }
}

final bleConnectionProvider =
    NotifierProvider<BleConnectionNotifier, BleConnectionState>(
      BleConnectionNotifier.new,
    );
