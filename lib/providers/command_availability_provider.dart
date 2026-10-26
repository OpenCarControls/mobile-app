import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:protobuf/protobuf.dart';

/// How long an availability report is trusted over BLE, which is synced quickly:
/// the device repeats it every 5 s, so this is three missed repeats.
const kCommandAvailabilityStaleAfter = Duration(seconds: 15);

/// How long an availability report is trusted over [transport]. MQTT isn't synced
/// as fast or as often as BLE (the device sends at a lower rate while the app is
/// in the background, and the link is slower), so there it expires with the
/// vehicle state: [kStateLivenessTimeout].
Duration commandAvailabilityStaleAfter(TransportType transport) =>
    transport == TransportType.mqtt
    ? kStateLivenessTimeout
    : kCommandAvailabilityStaleAfter;

/// The two command sets of a vehicle, as the device reports them.
enum CommandSet { basic, advanced }

/// What the UI does with a command's button.
enum CommandUiState {
  /// The device accepts the command now (or only the device can tell).
  enabled,

  /// Shown greyed out, without a reason.
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
/// cleared again if the device goes quiet for [commandAvailabilityStaleAfter].
/// A command shown as available must be one the device just said it accepts.
/// Over MQTT the device reports the basic commands only.
class CommandAvailabilityNotifier extends Notifier<CommandAvailability?> {
  Timer? _staleTimer;
  Duration _staleAfter = kCommandAvailabilityStaleAfter;

  @override
  CommandAvailability? build() {
    final transport = ref.watch(carTransportProvider);
    ref.onDispose(() => _staleTimer?.cancel());
    _staleAfter = commandAvailabilityStaleAfter(transport.transportType);
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
    _staleTimer?.cancel();
    _staleTimer = Timer(_staleAfter, () => state = null);
  }
}

final commandAvailabilityProvider =
    NotifierProvider<CommandAvailabilityNotifier, CommandAvailability?>(
      CommandAvailabilityNotifier.new,
    );

/// What to do with the button of command [id] in [set], given what the device
/// [reported] on the current connection (null if nothing yet).
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
  int id,
) {
  final state = switch (set) {
    CommandSet.basic => reported?.basic[id],
    CommandSet.advanced => reported?.advanced[id],
  };
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
  return commandUiState(reported, transport, key.set, key.id);
});

extension on TransportType {
  /// Whether the device reports command availability over this transport.
  bool get waitsForAvailability =>
      this == TransportType.ble || this == TransportType.mqtt;
}
