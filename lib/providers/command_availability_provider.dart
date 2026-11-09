import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/config/unsupported_commands_config.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/can_access_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/phone_access_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:protobuf/protobuf.dart';

/// The two command sets of a vehicle, as the device reports them.
enum CommandSet { basic, advanced }

/// What the UI does with a command's button.
enum CommandUiState {
  /// The device accepts the command now (or only the device can tell).
  enabled,

  /// Shown greyed out. A tap says why, when the app knows
  /// ([commandUnavailableReason]).
  disabled,

  /// Not available on this car: not shown.
  hidden,
}

/// The device's command availability (`SystemState.command_availability`):
/// which commands it accepts right now.
///
/// Like [canAccessStateProvider] it is kept apart from the cached snapshot and
/// never cached: it is null until the device reports it on the current
/// connection, cleared whenever the transport or connection changes, and
/// cleared again when the device goes quiet for as long as the vehicle state
/// takes to go stale ([kStateLivenessTimeout]), whatever the transport.
/// A command shown as available must be one the device just said it accepts.
/// Over MQTT the device reports the basic commands only.
class CommandAvailabilityNotifier extends Notifier<CommandAvailability?> {
  Timer? _staleTimer;

  @override
  CommandAvailability? build() {
    final transport = ref.watch(carTransportProvider);
    ref.onDispose(() => _staleTimer?.cancel());
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
    if (!system.hasCommandAvailability()) return;
    // The maps merge per command: a report may carry only what changed.
    state = CommandAvailability()
      ..mergeFromMessage(state ?? CommandAvailability())
      ..mergeFromMessage(system.commandAvailability);
    final vehicleKey = ref.read(pairedVehicleProvider)?.storageKey;
    if (vehicleKey != null) {
      ref
          .read(unsupportedCommandsProvider.notifier)
          .record(vehicleKey, system.commandAvailability);
    }
    _staleTimer?.cancel();
    _staleTimer = Timer(kStateLivenessTimeout, () => state = null);
  }
}

final commandAvailabilityProvider =
    NotifierProvider<CommandAvailabilityNotifier, CommandAvailability?>(
      CommandAvailabilityNotifier.new,
    );

/// The commands each vehicle doesn't have, by storage key, as encoded by
/// [_unsupportedId]. Loaded before [runApp].
final initialUnsupportedCommandsProvider = Provider<UnsupportedCommands>(
  (_) => const {},
);

/// Which commands each vehicle doesn't have, remembered from its availability
/// reports. A car's equipment doesn't change, so unlike the availability this
/// is kept across connections and app runs, and offline the app still knows
/// what to leave out. It can only hide a command, never enable one.
class UnsupportedCommandsNotifier extends Notifier<UnsupportedCommands> {
  @override
  UnsupportedCommands build() => ref.read(initialUnsupportedCommandsProvider);

  /// Updates [vehicleKey]'s commands from a [report]. Only `AVAILABLE` takes a
  /// command back: the device also reports `UNAVAILABLE` for every command
  /// while the phone isn't validated, which says nothing about the car.
  void record(String vehicleKey, CommandAvailability report) {
    final previous = state[vehicleKey] ?? const <String>{};
    final next = {...previous};
    void apply(CommandSet set, Map<int, CommandAvailabilityState> states) {
      for (final MapEntry(key: id, value: availability) in states.entries) {
        final key = _unsupportedId((set: set, id: id));
        switch (availability) {
          case CommandAvailabilityState.COMMAND_AVAILABILITY_STATE_UNSUPPORTED:
            next.add(key);
          case CommandAvailabilityState.COMMAND_AVAILABILITY_STATE_AVAILABLE:
            next.remove(key);
          default:
        }
      }
    }

    apply(CommandSet.basic, report.basic);
    apply(CommandSet.advanced, report.advanced);
    if (next.length == previous.length && next.containsAll(previous)) return;
    state = {...state, vehicleKey: next};
    unawaited(saveUnsupportedCommands(vehicleKey, next));
  }
}

final unsupportedCommandsProvider =
    NotifierProvider<UnsupportedCommandsNotifier, UnsupportedCommands>(
      UnsupportedCommandsNotifier.new,
    );

String _unsupportedId(CommandKey key) => '${key.set.name}/${key.id}';

/// What to do with the button of command [id] in [set], given what the device
/// [reported] on the current connection (null if nothing yet) and whether the
/// car is [knownUnsupported] from an earlier report.
///
/// Over BLE and MQTT the app waits for the device: a command is enabled only
/// while the device says it accepts it, so right after connecting, or when the
/// device goes quiet, the buttons are greyed out. An unspecified state counts as
/// not available. The stub and HTTP debug transports may not send availability,
/// so there the device decides and rejects what it can't do.
CommandUiState commandUiState(
  CommandAvailability? reported,
  TransportType transport,
  CommandSet set,
  int id, {
  bool knownUnsupported = false,
}) {
  final state = switch (set) {
    CommandSet.basic => reported?.basic[id],
    CommandSet.advanced => reported?.advanced[id],
  };
  if (knownUnsupported &&
      state != CommandAvailabilityState.COMMAND_AVAILABILITY_STATE_AVAILABLE) {
    return CommandUiState.hidden;
  }
  // Nothing reported for this command (yet): not known to be available.
  if (state == null) {
    return transport.waitsForAvailability
        ? CommandUiState.disabled
        : CommandUiState.enabled;
  }
  return switch (state) {
    CommandAvailabilityState.COMMAND_AVAILABILITY_STATE_AVAILABLE =>
      CommandUiState.enabled,
    CommandAvailabilityState.COMMAND_AVAILABILITY_STATE_UNSUPPORTED =>
      CommandUiState.hidden,
    _ => CommandUiState.disabled,
  };
}

/// Identifies a command: its set and its field number in the vehicle's command
/// oneof, which is how the device names it.
typedef CommandKey = ({CommandSet set, int id});

/// The field number of [fieldName] in [message]'s proto, i.e. the command id the
/// device uses in its availability report. Read from the generated message so
/// it can't drift from the contracts.
int commandId(GeneratedMessage message, String fieldName) {
  final tag = message.info_.tagNumber(fieldName);
  if (tag == null) {
    throw ArgumentError.value(fieldName, 'fieldName', 'not a field of message');
  }
  return tag;
}

/// What to do with the button of [key], from the live availability.
final commandUiStateProvider = Provider.family<CommandUiState, CommandKey>((
  ref,
  key,
) {
  final reported = ref.watch(commandAvailabilityProvider);
  final transport = ref.watch(carTransportProvider).transportType;
  final vehicleKey = ref.watch(pairedVehicleProvider)?.storageKey;
  final unsupported = ref.watch(unsupportedCommandsProvider)[vehicleKey];
  return commandUiState(
    reported,
    transport,
    key.set,
    key.id,
    knownUnsupported: unsupported?.contains(_unsupportedId(key)) ?? false,
  );
});

/// Why a greyed-out command in [set] can't be sent. The device doesn't report a
/// reason, so this is what the app knows from the transport and the access
/// states.
String commandUnavailableReason({
  required TransportType transport,
  required CommandSet set,
  required CanAccessState? canAccess,
  required PhoneAccessState? phoneAccess,
}) {
  if (transport == TransportType.mqtt && set == CommandSet.advanced) {
    return 'This needs a Bluetooth connection to the car.';
  }
  if (canAccess != null && canAccessNeedsApproval(canAccess)) {
    return "Control of this car isn't approved yet.";
  }
  if (phoneAccess?.trust == PhoneTrustLevel.PHONE_TRUST_LEVEL_BONDED) {
    return "This phone isn't validated in this car yet.";
  }
  return 'Not available right now.';
}

/// Validating this phone is what a greyed-out command is waiting for. The
/// approval comes first, like in [commandUnavailableReason].
final commandNeedsValidationProvider = Provider<bool>((ref) {
  final canAccess = ref.watch(canAccessStateProvider);
  if (canAccess != null && canAccessNeedsApproval(canAccess)) return false;
  return ref.watch(phoneAccessStateProvider)?.trust ==
      PhoneTrustLevel.PHONE_TRUST_LEVEL_BONDED;
});

/// The reason for [commandUnavailableReason], from the live state.
final commandUnavailableReasonProvider = Provider.family<String, CommandKey>((
  ref,
  key,
) {
  return commandUnavailableReason(
    transport: ref.watch(carTransportProvider).transportType,
    set: key.set,
    canAccess: ref.watch(canAccessStateProvider),
    phoneAccess: ref.watch(phoneAccessStateProvider),
  );
});

extension on TransportType {
  /// Whether the device reports command availability over this transport.
  bool get waitsForAvailability =>
      this == TransportType.ble || this == TransportType.mqtt;
}
