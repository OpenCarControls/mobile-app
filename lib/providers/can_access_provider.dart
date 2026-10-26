import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';

final _approved = CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_APPROVED;
final _notApproved = CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_NOT_APPROVED;
final _otherCar = CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_OTHER_CAR;

/// The device's CAN access state: whether it may transmit on the car's bus and
/// which conditions hold (see the firmware's docs/can.md, "Read-write policy").
///
/// Kept apart from [vehicleStateProvider]'s snapshot and never cached: it is
/// null until the device reports it on the current connection, and cleared
/// whenever the transport or connection changes. A cached or earlier value
/// could claim control is enabled when the device has since restarted
/// read-only. Always null over MQTT, which carries no system state. The device
/// repeats it every few seconds.
class CanAccessStateNotifier extends Notifier<CanAccessState?> {
  @override
  CanAccessState? build() {
    final transport = ref.watch(carTransportProvider);
    if (transport.transportType == TransportType.mqtt) return null;
    final platformId = ref.read(selectedVehicleProvider)?.platformId;
    final subscription = transport.messages.listen(
      (msg) => _onMessage(msg, platformId),
    );
    ref.onDispose(subscription.cancel);
    return null;
  }

  void _onMessage(DeviceToApp msg, int? platformId) {
    // Like vehicleStateProvider, ignore a device reporting another platform.
    if (platformId != null &&
        msg.platformId != 0 &&
        msg.platformId != platformId) {
      return;
    }
    if (!msg.hasStateUpdate() || !msg.stateUpdate.hasSystemState()) return;
    final system = msg.stateUpdate.systemState;
    if (!system.hasCanAccess()) return;
    // Fields are optional: merge into what this connection reported so far.
    state = CanAccessState()
      ..mergeFromMessage(state ?? CanAccessState())
      ..mergeFromMessage(system.canAccess);
  }
}

final canAccessStateProvider =
    NotifierProvider<CanAccessStateNotifier, CanAccessState?>(
      CanAccessStateNotifier.new,
    );

/// Why the device is read-only, or that control is enabled, in a few words.
String canAccessSummary(CanAccessState state) {
  if (!state.readOnly) return 'Control enabled';
  if (state.logging) return 'Read-only: CAN logging is active';
  if (!state.platformConfirmed) {
    return 'Read-only: the car platform is not recognised yet';
  }
  if (!state.carIdentityConfirmed) {
    return 'Read-only: the car is not identified yet';
  }
  if (state.approval == _otherCar) {
    return 'Read-only: control was approved for a different car';
  }
  if (state.approval != _approved) {
    return 'Read-only: control is not approved for this car';
  }
  if (state.devLockAvailable && !state.devUnlocked) {
    return 'Read-only: the developer write lock is locked';
  }
  return 'Read-only: waiting for the vehicle to enable control';
}

/// True when the owner can approve control now: the car is identified and the
/// approval is missing or was given for another car.
bool canAccessNeedsApproval(CanAccessState state) {
  if (!state.carIdentityConfirmed) return false;
  return state.approval == _notApproved || state.approval == _otherCar;
}

/// Sends the CAN read-write policy commands. BLE only; they fail with the
/// device's reason (e.g. the car is not identified, or this phone isn't
/// bonded).
class CanAccessActions {
  final Ref _ref;
  const CanAccessActions(this._ref);

  /// Approves (`true`) or revokes (`false`) CAN read-write mode for the car the
  /// device is plugged into. Show the risk warning before approving.
  Future<void> setApproval(bool approved) async {
    final approval = SetCanReadWriteApprovalCommand(approved: approved);
    await _send(SystemCommand(setCanReadWriteApproval: approval));
  }

  /// Unlocks (`true`) or locks (`false`) the developer write lock. Only in
  /// development firmware builds ([CanAccessState.devLockAvailable]).
  Future<void> setDevWriteUnlocked(bool unlocked) async {
    final unlock = SetCanDevWriteUnlockCommand(unlocked: unlocked);
    await _send(SystemCommand(setCanDevWriteUnlock: unlock));
  }

  Future<void> _send(SystemCommand command) async {
    final notifier = _ref.read(vehicleStateProvider.notifier);
    await notifier.sendSystemCommand(command);
  }
}

final canAccessActionsProvider = Provider<CanAccessActions>(
  CanAccessActions.new,
);
