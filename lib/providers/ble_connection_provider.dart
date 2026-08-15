import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  const BleReady(this.deviceId);
}

/// Not connected and not attempting to connect (BLE unavailable, disabled,
/// no paired device, or device paired via HTTP transport).
/// [warning] carries a human-readable reason when set.
class BleDisconnected extends BleConnectionState {
  final String? warning;
  const BleDisconnected({this.warning});
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class BleConnectionNotifier extends Notifier<BleConnectionState> {
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<BleStatus>? _statusSubscription;
  bool _connecting = false;
  bool _disposed = false;

  @override
  BleConnectionState build() {
    final config = ref.watch(pairedVehicleProvider);

    // No paired device, or user prefers HTTP — BLE not needed.
    if (config == null ||
        config.transportPreference == TransportPreference.http ||
        config.bleRemoteId.isEmpty) {
      return const BleDisconnected();
    }

    ref.onDispose(_cleanup);
    unawaited(_initConnection(config.bleRemoteId));
    return BleConnecting(config.bleRemoteId);
  }

  Future<void> _initConnection(String remoteId) async {
    final granted = await _requestPermissions();
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
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connecting = false;
  }

  void _connectDirectly(String remoteId) {
    if (_connecting) return;
    _connecting = true;
    state = BleConnecting(remoteId);

    final ble = ref.read(bleProvider);
    dev.log('Connecting to $remoteId', name: 'BleConnection');

    // connectToDevice emits updates for the lifetime of the subscription and
    // automatically retries when the device is out of range — no manual
    // reconnect timer needed.
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
            // Reconnect after a short delay
            Future.delayed(const Duration(seconds: 30), () {
              if (!_disposed) _connectDirectly(remoteId);
            });
          },
          onDone: () {
            dev.log('Connection stream done', name: 'BleConnection');
            _connecting = false;
            state = BleConnecting(remoteId);
            // Reconnect after a short delay
            Future.delayed(const Duration(seconds: 30), () {
              if (!_disposed) _connectDirectly(remoteId);
            });
          },
        );
  }

  void forceReconnect() {
    if (_disposed) return;
    if (state is BleReady) {
      dev.log('Already connected, ignoring force reconnect', name: 'BleConnection');
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
      // Negotiate MTU before emitting BleReady.
      await ble.requestMtu(deviceId: remoteId, mtu: 244);
      dev.log('MTU negotiated for $remoteId', name: 'BleConnection');

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

      // Verify the required characteristics are present.
      final vehicle = ref.read(selectedVehicleProvider);
      if (vehicle == null) {
        dev.log('No vehicle selected — cannot verify characteristics');
        state = const BleDisconnected();
        _connecting = false;
        return;
      }

      final services = await ble.getDiscoveredServices(remoteId);
      final serviceUuid = Uuid.parse(vehicle.bleServiceUuid);
      final serviceMatch = services.where((s) => s.id == serviceUuid);
      if (serviceMatch.isEmpty) {
        throw StateError(
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
        throw StateError(
          'Required BLE characteristics not found in service '
          '${vehicle.bleServiceUuid}',
        );
      }

      dev.log('BLE ready: $remoteId', name: 'BleConnection');
      state = BleReady(remoteId);
      _connecting = false;
    } on Exception catch (e) {
      dev.log('Post-connect init failed: $e', name: 'BleConnection');
      _connecting = false;
      state = BleConnecting(remoteId);
    }
  }

  void _cleanup() {
    _disposed = true;
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
