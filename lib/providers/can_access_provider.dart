import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';

/// The device's CAN access state: whether it may transmit on the car's bus and
/// which conditions hold (see the firmware's docs/can.md, "Read-write policy").
///
/// Null unless the device reported it in this live session over a transport
/// that carries system state (BLE, or the debug HTTP and stub transports): a
/// cached value could claim control is enabled when it no longer is.
final canAccessStateProvider = Provider<CanAccessState?>((ref) {
  final transportType = ref.watch(transportTypeProvider);
  if (transportType == TransportType.mqtt) return null;
  final snapshot = ref.watch(vehicleStateProvider);
  final system = snapshot.system;
  if (!snapshot.isStateLive || system == null || !system.hasCanAccess()) {
    return null;
  }
  return system.canAccess;
});

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
  if (state.approval ==
      CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_OTHER_CAR) {
    return 'Read-only: control was approved for a different car';
  }
  if (state.approval !=
      CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_APPROVED) {
    return 'Read-only: control is not approved for this car';
  }
  if (state.devLockAvailable && !state.devUnlocked) {
    return 'Read-only: the developer write lock is locked';
  }
  return 'Read-only: waiting for the vehicle to enable control';
}

/// True when the owner can approve control now: the car is identified and the
/// approval is missing or was given for another car.
bool canAccessNeedsApproval(CanAccessState state) =>
    state.carIdentityConfirmed &&
    (state.approval ==
            CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_NOT_APPROVED ||
        state.approval ==
            CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_OTHER_CAR);

/// Sends the CAN read-write policy commands. BLE only; they fail with the
/// device's reason (e.g. the car is not identified, or this phone isn't
/// bonded).
class CanAccessActions {
  final Ref _ref;
  const CanAccessActions(this._ref);

  /// Approves (`true`) or revokes (`false`) CAN read-write mode for the car the
  /// device is plugged into. Show the risk warning before approving.
  Future<void> setApproval(bool approved) => _ref
      .read(vehicleStateProvider.notifier)
      .sendSystemCommand(
        SystemCommand(
          setCanReadWriteApproval: SetCanReadWriteApprovalCommand(
            approved: approved,
          ),
        ),
      );

  /// Unlocks (`true`) or locks (`false`) the developer write lock. Only in
  /// development firmware builds ([CanAccessState.devLockAvailable]).
  Future<void> setDevWriteUnlocked(bool unlocked) => _ref
      .read(vehicleStateProvider.notifier)
      .sendSystemCommand(
        SystemCommand(
          setCanDevWriteUnlock: SetCanDevWriteUnlockCommand(unlocked: unlocked),
        ),
      );
}

final canAccessActionsProvider = Provider<CanAccessActions>(
  CanAccessActions.new,
);
