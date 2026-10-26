import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protobuf/protobuf.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/transport/car_transport.dart';

class VehicleSnapshot {
  /// Decoded vehicle-specific basic state. Cast to the vehicle's BasicState
  /// type in the vehicle's own screen (e.g. `snapshot.basicState as BasicState`).
  final GeneratedMessage basicState;

  /// Decoded vehicle-specific advanced state. Cast in the vehicle's own screen.
  final GeneratedMessage advancedState;

  /// Core system state (firmware version, hardware type, uptime).
  /// Null until the first BLE state update is received.
  final SystemState? system;

  /// When this snapshot was last populated from a live device message.
  /// Null if only the persisted cache has been restored (no live update yet
  /// this session) — though the cached value itself carries the timestamp.
  final DateTime? lastUpdated;

  /// True once [advancedState] has been received over the current live
  /// transport session. Reset to false on every transport switch.
  ///
  /// Vehicle screens should gate their advanced state and advanced controls
  /// sections on this flag (in addition to checking the transport type)
  /// so that stale cached values are never shown or acted on before the
  /// firmware has sent a fresh update.
  final bool isAdvancedStateLive;

  /// True once ANY state has been received over the current live
  /// transport session. Reset to false on every transport switch.
  final bool isStateLive;

  /// Set when the device reported a `platform_id` that doesn't match the
  /// paired vehicle. Its messages are ignored until the user re-pairs.
  final int? mismatchedPlatformId;

  const VehicleSnapshot({
    required this.basicState,
    required this.advancedState,
    this.system,
    this.lastUpdated,
    this.isAdvancedStateLive = false,
    this.isStateLive = false,
    this.mismatchedPlatformId,
  });

  VehicleSnapshot copyWith({
    GeneratedMessage? basicState,
    GeneratedMessage? advancedState,
    SystemState? system,
    DateTime? lastUpdated,
    bool? isAdvancedStateLive,
    bool? isStateLive,
    int? mismatchedPlatformId,
  }) {
    return VehicleSnapshot(
      basicState: basicState ?? this.basicState,
      advancedState: advancedState ?? this.advancedState,
      system: system ?? this.system,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isAdvancedStateLive: isAdvancedStateLive ?? this.isAdvancedStateLive,
      isStateLive: isStateLive ?? this.isStateLive,
      mismatchedPlatformId: mismatchedPlatformId ?? this.mismatchedPlatformId,
    );
  }
}

/// How long the vehicle state stays live without an update from the device. The command
/// availability expires with it, over BLE and MQTT alike.
const kStateLivenessTimeout = Duration(seconds: 30);

class VehicleStateNotifier extends Notifier<VehicleSnapshot> {
  StreamSubscription<DeviceToApp>? _subscription;
  Timer? _livenessTimer;
  // Random start so IDs aren't reused across app restarts (a late response
  // to a previous session's command must not complete a new one). Stays well
  // below 2^32, which is where MQTT heartbeat IDs start.
  int _nextMessageId = Random().nextInt(1 << 31);
  final _pendingCommands = <Int64, Completer<CommandResponse>>{};
  // Cached across rebuilds so teardown races (vehicle → null before
  // this notifier is disposed) don't crash build().
  VehicleDefinition? _vehicle;
  // Preserved across transport switches so the UI doesn't flash blank
  // while waiting for the first state update on the new transport.
  VehicleSnapshot? _lastSnapshot;
  // Used to discard async cache loads that complete after a vehicle change.
  int _buildGeneration = 0;

  static const _kStateCacheKeyPrefix = 'vehicle_state_';

  @override
  VehicleSnapshot build() {
    final latestVehicle = ref.read(selectedVehicleProvider);
    // Discard stale cache when the paired vehicle changes.
    if (latestVehicle != null &&
        latestVehicle.platformName != _vehicle?.platformName) {
      _lastSnapshot = null;
    }
    if (latestVehicle != null) _vehicle = latestVehicle;
    final vehicle = _vehicle!;
    final transport = ref.watch(carTransportProvider);

    _subscription = transport.messages.listen(_onMessage);
    ref.onDispose(() {
      _subscription?.cancel();
      _livenessTimer?.cancel();
      for (final completer in _pendingCommands.values) {
        if (!completer.isCompleted) {
          completer.completeError('Provider disposed');
        }
      }
      _pendingCommands.clear();
    });

    // On cold start (no in-memory cache yet) kick off an async restore
    // from SharedPreferences. A generation counter ensures a late-arriving
    // load from a previous vehicle doesn't overwrite a newer one.
    final generation = ++_buildGeneration;
    if (_lastSnapshot == null) {
      _loadCachedState(vehicle, generation);
    }

    // Restore the last known state on transport switches so the UI doesn't
    // flash blank while waiting for the first update on the new transport.
    // Fall back to empty defaults only on the very first build.
    // isAdvancedStateLive is always reset to false: the cached advanced state
    // must not be shown until the firmware confirms it over the new transport.
    final base =
        _lastSnapshot ??
        VehicleSnapshot(
          basicState: vehicle.decodeBasicState(const []),
          advancedState: vehicle.decodeAdvancedState(const []),
        );
    return base.copyWith(isAdvancedStateLive: false, isStateLive: false);
  }

  void _onMessage(DeviceToApp msg) {
    if (msg.hasCommandResponse()) {
      final response = msg.commandResponse;
      final completer = _pendingCommands.remove(response.messageId);
      if (completer != null && !completer.isCompleted) {
        if (!response.success) {
          completer.completeError(
            response.errorMessage.isNotEmpty
                ? response.errorMessage
                : 'Command failed',
          );
        } else {
          completer.complete(response);
        }
      }
    }

    final vehicle = _vehicle!;
    if (msg.platformId != 0 && msg.platformId != vehicle.platformId) {
      if (state.mismatchedPlatformId != msg.platformId) {
        dev.log(
          'Platform ID mismatch: expected ${vehicle.platformId}, '
          'got ${msg.platformId}. Ignoring device messages.',
          name: 'VehicleState',
        );
        state = state.copyWith(mismatchedPlatformId: msg.platformId);
      }
      return;
    }

    if (!msg.hasStateUpdate()) return;

    _livenessTimer?.cancel();
    _livenessTimer = Timer(kStateLivenessTimeout, () {
      if (state.isStateLive || state.isAdvancedStateLive) {
        state = state.copyWith(isStateLive: false, isAdvancedStateLive: false);
      }
    });

    if (kDebugMode) {
      final u = msg.stateUpdate;
      final fields = [
        if (u.hasVehicleState() && u.vehicleState.basicStateBytes.isNotEmpty)
          'basicState',
        if (u.hasVehicleState() && u.vehicleState.advancedStateBytes.isNotEmpty)
          'advancedState',
        if (u.hasSystemState()) 'system',
      ];
      dev.log(
        'State update received: ${fields.isEmpty ? '(no known fields)' : fields.join(', ')}',
        name: 'VehicleState',
      );
    }

    final update = msg.stateUpdate;
    var current = state;

    if (update.hasVehicleState()) {
      final vs = update.vehicleState;

      if (vs.basicStateBytes.isNotEmpty) {
        // Decode once; merge into a fresh copy of the current state.
        final merged = vehicle.decodeBasicState(const [])
          ..mergeFromMessage(current.basicState)
          ..mergeFromBuffer(vs.basicStateBytes);
        current = current.copyWith(basicState: merged);
      }

      if (vs.advancedStateBytes.isNotEmpty) {
        final merged = vehicle.decodeAdvancedState(const [])
          ..mergeFromMessage(current.advancedState)
          ..mergeFromBuffer(vs.advancedStateBytes);
        current = current.copyWith(
          advancedState: merged,
          isAdvancedStateLive: true,
        );
      }
    }

    if (update.hasSystemState()) {
      final merged = SystemState()
        ..mergeFromMessage(current.system ?? SystemState())
        ..mergeFromMessage(update.systemState);
      current = current.copyWith(system: merged);
    }

    current = current.copyWith(lastUpdated: DateTime.now(), isStateLive: true);
    // Persist isAdvancedStateLive=false so a restored cache never starts live.
    _lastSnapshot = current;
    state = current;

    if (kDebugMode) {
      dev.log(
        'Updated State JSON:\nbasicState=${jsonEncode(current.basicState.toProto3Json())}\nadvancedState=${jsonEncode(current.advancedState.toProto3Json())}',
        name: 'VehicleState',
      );
    }

    _saveCachedState(current, vehicle);
  }

  Future<void> _loadCachedState(
    VehicleDefinition vehicle,
    int generation,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(
        '$_kStateCacheKeyPrefix${vehicle.platformName}',
      );
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final basicState = vehicle.decodeBasicState(
        base64Decode(json['basicStateBytes'] as String),
      );
      final advancedState = vehicle.decodeAdvancedState(
        base64Decode(json['advancedStateBytes'] as String),
      );
      final systemBytesRaw = json['systemStateBytes'] as String?;
      final system = systemBytesRaw != null
          ? (SystemState()..mergeFromBuffer(base64Decode(systemBytesRaw)))
          : null;
      final lastUpdated = DateTime.tryParse(
        (json['lastUpdated'] as String?) ?? '',
      );
      // Only apply if the provider is still alive, no live update arrived
      // first and the vehicle hasn't changed.
      if (!ref.mounted ||
          _lastSnapshot != null ||
          _buildGeneration != generation) {
        return;
      }
      _lastSnapshot = VehicleSnapshot(
        basicState: basicState,
        advancedState: advancedState,
        system: system,
        lastUpdated: lastUpdated,
      );
      state = _lastSnapshot!;
    } catch (e) {
      dev.log('Failed to restore cached state: $e', name: 'VehicleState');
    }
  }

  Future<void> _saveCachedState(
    VehicleSnapshot snapshot,
    VehicleDefinition vehicle,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = <String, dynamic>{
        'basicStateBytes': base64Encode(snapshot.basicState.writeToBuffer()),
        'advancedStateBytes': base64Encode(
          snapshot.advancedState.writeToBuffer(),
        ),
        if (snapshot.system != null)
          'systemStateBytes': base64Encode(snapshot.system!.writeToBuffer()),
        if (snapshot.lastUpdated != null)
          'lastUpdated': snapshot.lastUpdated!.toUtc().toIso8601String(),
      };
      await prefs.setString(
        '$_kStateCacheKeyPrefix${vehicle.platformName}',
        jsonEncode(json),
      );
    } catch (e) {
      dev.log('Failed to persist state cache: $e', name: 'VehicleState');
    }
  }

  /// Send a serialised basic command for the active vehicle.
  /// The caller (vehicle-specific screen) is responsible for serialising the
  /// vehicle's own proto command type: `myCommand.writeToBuffer()`.
  Future<CommandResponse> sendBasicCommand(List<int> commandBytes) async {
    final messageId = Int64(_nextMessageId++);
    final completer = Completer<CommandResponse>();
    _pendingCommands[messageId] = completer;

    try {
      await _send(
        AppToDevice(
          messageId: messageId,
          platformId: vehicle.platformId,
          basicCommandBytes: commandBytes,
        ),
      );
    } catch (e) {
      _pendingCommands.remove(messageId);
      rethrow;
    }

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pendingCommands.remove(messageId);
        throw TimeoutException('Command timed out');
      },
    );
  }

  /// Send a serialised advanced command for the active vehicle.
  /// Only meaningful over BLE; the BLE transport sends all envelope types.
  Future<CommandResponse> sendAdvancedCommand(List<int> commandBytes) async {
    final messageId = Int64(_nextMessageId++);
    final completer = Completer<CommandResponse>();
    _pendingCommands[messageId] = completer;

    try {
      await _send(
        AppToDevice(
          messageId: messageId,
          platformId: vehicle.platformId,
          advancedCommandBytes: commandBytes,
        ),
      );
    } catch (e) {
      _pendingCommands.remove(messageId);
      rethrow;
    }

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pendingCommands.remove(messageId);
        throw TimeoutException('Command timed out');
      },
    );
  }

  /// Send a system command (e.g. the CAN read-write approval). BLE only: the
  /// firmware drops system commands from MQTT, so this throws
  /// [CarTransportException] instead of waiting for the timeout.
  Future<CommandResponse> sendSystemCommand(SystemCommand command) async {
    if (ref.read(transportTypeProvider) == TransportType.mqtt) {
      throw const CarTransportException(
        'This needs a Bluetooth connection to the vehicle.',
      );
    }
    final messageId = Int64(_nextMessageId++);
    final completer = Completer<CommandResponse>();
    _pendingCommands[messageId] = completer;

    try {
      await _send(
        AppToDevice(
          messageId: messageId,
          platformId: vehicle.platformId,
          systemCommand: command,
        ),
      );
    } catch (e) {
      _pendingCommands.remove(messageId);
      rethrow;
    }

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pendingCommands.remove(messageId);
        throw TimeoutException('Command timed out');
      },
    );
  }

  Future<void> _send(AppToDevice envelope) {
    final transportType = ref.read(transportTypeProvider);
    if (transportType == TransportType.ble ||
        transportType == TransportType.http) {
      envelope.sourceDeviceId = ref.read(bleSourceDeviceIdProvider);
    }
    if (kDebugMode) {
      final kind = envelope.hasBasicCommandBytes()
          ? 'basic'
          : envelope.hasSystemCommand()
          ? 'system'
          : 'advanced';
      dev.log(
        'Sending $kind command (msgId: ${envelope.messageId}) via $transportType',
        name: 'VehicleState',
      );
    }
    return ref.read(carTransportProvider).send(envelope);
  }

  VehicleDefinition get vehicle => _vehicle!;

  /// Debug only: replaces the basic state locally (no device involved) to
  /// exercise the UI and 3D animations. [basicState] must be the vehicle's own
  /// BasicState type. The next live update overwrites it.
  void debugOverrideBasicState(GeneratedMessage basicState) {
    assert(kDebugMode, 'debugOverrideBasicState is debug-only');
    state = state.copyWith(basicState: basicState);
    _saveCachedState(state, vehicle);
  }
}

final vehicleStateProvider =
    NotifierProvider<VehicleStateNotifier, VehicleSnapshot>(
      VehicleStateNotifier.new,
    );
