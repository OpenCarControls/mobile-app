import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Transport constants are identical in every vehicle's constants.g.dart.
import 'package:open_car_app/cars/virtual_car/constants.g.dart'
    show kBleAttMtu, kBleMinAttMtu;
import 'package:open_car_app/config/paired_vehicle_config.dart';
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

// ── Notifier ──────────────────────────────────────────────────────────────────

class BleConnectionNotifier extends Notifier<BleConnectionState> {
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<BleStatus>? _statusSubscription;
  bool _connecting = false;
  bool _disposed = false;
  // Pending retry after the connection stream ends. Only one may be scheduled,
  // and any new connection attempt cancels it.
  Timer? _retryTimer;

  @override
  BleConnectionState build() {
    final config = ref.watch(pairedVehicleProvider);

    // No paired device, or user prefers HTTP — BLE not needed.
    if (config == null ||
        config.transportPreference == TransportPreference.http ||
        config.bleRemoteId.isEmpty) {
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

  void _cancelConnection() {
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
            _connecting = false;
            state = BleConnecting(remoteId);
            _scheduleRetry(remoteId);
          },
          onDone: () {
            dev.log('Connection stream done', name: 'BleConnection');
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
    if (config == null || config.bleRemoteId.isEmpty) return;
    dev.log('Force reconnect requested', name: 'BleConnection');
    _cancelConnection();
    _connectDirectly(config.bleRemoteId);
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
        await _onConnected(remoteId);
      case DeviceConnectionState.disconnected:
        dev.log('Disconnected from $remoteId', name: 'BleConnection');
        _connecting = false;
        // connectToDevice will reconnect automatically while the subscription
        // lives — just reset to connecting state.
        state = BleConnecting(remoteId);
      default:
        break;
    }
  }

  Future<void> _onConnected(String remoteId) async {
    final ble = ref.read(bleProvider);

    try {
      // Negotiate MTU before emitting BleReady. Messages are split into
      // chunks sized from it, so a smaller MTU only means more chunks, down to
      // kBleMinAttMtu: below that the device can't send its largest messages
      // and drops them.
      final mtu = await ble.requestMtu(deviceId: remoteId, mtu: kBleAttMtu);
      if (mtu < kBleMinAttMtu) {
        dev.log(
          'MTU $mtu negotiated for $remoteId, below the $kBleMinAttMtu BLE '
          'needs; the device will drop its messages and commands will fail',
          name: 'BleConnection',
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

      // Discover services and characteristics.
      await ble.discoverAllServices(remoteId);
      dev.log('Services discovered for $remoteId', name: 'BleConnection');
      if (!ref.mounted) return;

      // Verify the required characteristics are present.
      final vehicle = ref.read(selectedVehicleProvider);
      if (vehicle == null) {
        dev.log('No vehicle selected — cannot verify characteristics');
        state = const BleDisconnected();
        _connecting = false;
        return;
      }

      final services = await ble.getDiscoveredServices(remoteId);
      if (!ref.mounted) return;
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
      if (!ref.mounted) return;
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
