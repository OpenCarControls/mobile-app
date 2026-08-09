import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

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
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';

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

  const VehicleSnapshot({
    required this.basicState,
    required this.advancedState,
    this.system,
    this.lastUpdated,
    this.isAdvancedStateLive = false,
    this.isStateLive = false,
  });

  VehicleSnapshot copyWith({
    GeneratedMessage? basicState,
    GeneratedMessage? advancedState,
    SystemState? system,
    DateTime? lastUpdated,
    bool? isAdvancedStateLive,
    bool? isStateLive,
  }) {
    return VehicleSnapshot(
      basicState: basicState ?? this.basicState,
      advancedState: advancedState ?? this.advancedState,
      system: system ?? this.system,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isAdvancedStateLive: isAdvancedStateLive ?? this.isAdvancedStateLive,
      isStateLive: isStateLive ?? this.isStateLive,
    );
  }
}

class VehicleStateNotifier extends Notifier<VehicleSnapshot> {
  StreamSubscription<DeviceToApp>? _subscription;
  Timer? _livenessTimer;
  int _nextMessageId = 0;
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
          completer.completeError(response.errorMessage.isNotEmpty ? response.errorMessage : 'Command failed');
        } else {
          completer.complete(response);
        }
      }
    }

    if (!msg.hasStateUpdate()) return;

    _livenessTimer?.cancel();
    _livenessTimer = Timer(const Duration(seconds: 30), () {
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

    final vehicle = ref.read(selectedVehicleProvider)!;
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

    current = current.copyWith(
      lastUpdated: DateTime.now(),
      isStateLive: true,
    );
    // Persist isAdvancedStateLive=false so a restored cache never starts live.
    _lastSnapshot = current;
    state = current;
    _saveCachedState(current, ref.read(selectedVehicleProvider)!);
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
      // Only apply if no live update arrived first and the vehicle hasn't changed.
      if (_lastSnapshot != null || _buildGeneration != generation) return;
      _lastSnapshot = VehicleSnapshot(
        basicState: basicState,
        advancedState: advancedState,
        system: system,
        lastUpdated: lastUpdated,
      );
      try {
        state = _lastSnapshot!;
      } on StateError {
        // Provider disposed before the async load completed.
      }
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

  Future<void> _send(AppToDevice envelope) {
    final transportType = ref.read(transportTypeProvider);
    if (transportType == TransportType.ble ||
        transportType == TransportType.http) {
      envelope.sourceDeviceId = ref.read(bleSourceDeviceIdProvider);
    }
    if (kDebugMode) {
      final kind = envelope.hasBasicCommandBytes() ? 'basic' : 'advanced';
      dev.log(
        'Sending $kind command (msgId: ${envelope.messageId}) via $transportType',
        name: 'VehicleState',
      );
    }
    return ref.read(carTransportProvider).send(envelope);
  }

  VehicleDefinition get vehicle => ref.read(selectedVehicleProvider)!;

  /// Injects a test state directly into the provider to test UI/3D animations
  void injectTestState({
    bool? isDriverDoorOpen,
    bool? isPassengerDoorOpen,
    bool? isRearLeftDoorOpen,
    bool? isRearRightDoorOpen,
    bool? isDriverWindowOpen,
    bool? isPassengerWindowOpen,
    bool? isRearLeftWindowOpen,
    bool? isRearRightWindowOpen,
    bool? isFrunkOpen,
    bool? isTrunkOpen,
    BasicState_ChargePortState? chargePortState,
    bool? areLightsOn,
    bool? areHazardLightsOn,
    int? powerFlowWatt,
  }) {
    final currentBasic = state.basicState as BasicState;
    
    final newBasic = currentBasic.deepCopy();
    if (isDriverDoorOpen != null) newBasic.isDriverDoorOpen = isDriverDoorOpen;
    if (isPassengerDoorOpen != null) newBasic.isPassengerDoorOpen = isPassengerDoorOpen;
    if (isRearLeftDoorOpen != null) newBasic.isRearLeftDoorOpen = isRearLeftDoorOpen;
    if (isRearRightDoorOpen != null) newBasic.isRearRightDoorOpen = isRearRightDoorOpen;
    if (isDriverWindowOpen != null) newBasic.isDriverWindowOpen = isDriverWindowOpen;
    if (isPassengerWindowOpen != null) newBasic.isPassengerWindowOpen = isPassengerWindowOpen;
    if (isRearLeftWindowOpen != null) newBasic.isRearLeftWindowOpen = isRearLeftWindowOpen;
    if (isRearRightWindowOpen != null) newBasic.isRearRightWindowOpen = isRearRightWindowOpen;
    if (isFrunkOpen != null) newBasic.isFrunkOpen = isFrunkOpen;
    if (isTrunkOpen != null) newBasic.isTrunkOpen = isTrunkOpen;
    if (chargePortState != null) newBasic.chargePortState = chargePortState;
    if (areLightsOn != null) newBasic.areLightsOn = areLightsOn;
    if (areHazardLightsOn != null) newBasic.areHazardLightsOn = areHazardLightsOn;
    if (powerFlowWatt != null) newBasic.powerFlowWatt = powerFlowWatt;

    state = state.copyWith(basicState: newBasic);
    _saveCachedState(state, vehicle);
  }
}

final vehicleStateProvider =
    NotifierProvider<VehicleStateNotifier, VehicleSnapshot>(
      VehicleStateNotifier.new,
    );
