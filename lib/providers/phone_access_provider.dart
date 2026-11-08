import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/models/paired_phone.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';

/// What the device allows this phone (`SystemState.phone_access`): its trust
/// level, whether the car has a validated phone, and its validation session.
/// See the firmware's docs/ble.md, "Phone trust".
///
/// Like [canAccessStateProvider] it is kept apart from the cached snapshot and
/// never cached: it is null until the device reports it on the current
/// connection, and cleared whenever the transport or connection changes. Always
/// null over MQTT, which carries no system state. The device repeats it every
/// few seconds, with the CAN access state.
class PhoneAccessStateNotifier extends Notifier<PhoneAccessState?> {
  @override
  PhoneAccessState? build() {
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
    if (!system.hasPhoneAccess()) return;
    // Fields are optional: merge into what this connection reported so far.
    // Except the session, which is reported whole, and not at all once the
    // phone has none. Merging it would keep values that are now zero, which
    // aren't on the wire (the last attempt, the time left), or a session that
    // has ended.
    state = PhoneAccessState()
      ..mergeFromMessage(state ?? PhoneAccessState())
      ..clearValidation()
      ..mergeFromMessage(system.phoneAccess);
  }
}

final phoneAccessStateProvider =
    NotifierProvider<PhoneAccessStateNotifier, PhoneAccessState?>(
      PhoneAccessStateNotifier.new,
    );

/// Sends the phone validation commands. BLE only, like every system command:
/// over MQTT they fail without sending anything.
///
/// A command the device refuses throws [CommandRejectedException] with its
/// reason, and with the phone's session when that explains the refusal
/// ([CommandRejectedException.validationSession]): a wrong code, for example.
class PhoneValidationActions {
  final Ref _ref;
  const PhoneValidationActions(this._ref);

  /// The ways this car offers to validate a phone, in the order to offer them,
  /// with whether each can start now.
  Future<List<PhoneValidationMethod>> listMethods() async {
    final result = await _sendForResult(
      SystemCommand(
        listPhoneValidationMethods: ListPhoneValidationMethodsCommand(),
      ),
      SystemCommandResult_Result.validationMethods,
    );
    return result.validationMethods.methods;
  }

  /// Starts validating this phone with [methodId], from
  /// [PhoneValidationMethod.methodId]. Replaces this phone's running session.
  Future<PhoneValidationSession> start(String methodId) async {
    final start = StartPhoneValidationCommand(methodId: methodId);
    final result = await _sendForResult(
      SystemCommand(startPhoneValidation: start),
      SystemCommandResult_Result.validationSession,
    );
    return result.validationSession;
  }

  /// Submits the [code] the car shows, for a running code entry session.
  Future<PhoneValidationSession> submitCode(String code) async {
    final submit = SubmitPhoneValidationCodeCommand(code: code);
    final result = await _sendForResult(
      SystemCommand(submitPhoneValidationCode: submit),
      SystemCommandResult_Result.validationSession,
    );
    return result.validationSession;
  }

  /// Ends this phone's running session.
  Future<void> cancel() async {
    await _ref
        .read(vehicleStateProvider.notifier)
        .sendSystemCommand(
          SystemCommand(cancelPhoneValidation: CancelPhoneValidationCommand()),
        );
  }

  /// The phones bonded to the device, in bonding order.
  Future<List<PairedPhoneInfo>> listPairedPhones() async {
    final result = await _sendForResult(
      SystemCommand(listPairedPhones: ListPairedPhonesCommand()),
      SystemCommandResult_Result.pairedPhones,
    );
    return result.pairedPhones.phones.map(PairedPhoneInfo.fromProto).toList();
  }

  /// Asks the device to remove a phone's bond. It only answers a refusal, and
  /// ignores the request while its pairing window is closed: read the list
  /// again to see whether the phone is gone.
  Future<void> removePairedPhone(List<int> deviceId) => _ref
      .read(vehicleStateProvider.notifier)
      .sendUnansweredSystemCommand(
        SystemCommand(
          removePairedPhone: RemovePairedPhoneCommand(deviceId: deviceId),
        ),
      );

  Future<SystemCommandResult> _sendForResult(
    SystemCommand command,
    SystemCommandResult_Result expected,
  ) async {
    final notifier = _ref.read(vehicleStateProvider.notifier);
    final response = await notifier.sendSystemCommand(command);
    final result = response.systemResult;
    if (result.whichResult() != expected) {
      throw const CarTransportException(
        'The device did not send the expected answer.',
      );
    }
    return result;
  }
}

final phoneValidationActionsProvider = Provider<PhoneValidationActions>(
  PhoneValidationActions.new,
);

/// The phones bonded to the device, asked for on each connection and when this
/// phone's trust changes. BLE only: fails over MQTT.
final pairedPhonesProvider = FutureProvider.autoDispose<List<PairedPhoneInfo>>(
  (ref) {
    ref.watch(carTransportProvider);
    ref.watch(phoneAccessStateProvider.select((access) => access?.trust));
    return ref.read(phoneValidationActionsProvider).listPairedPhones();
  },
  // A failure is shown with a way to try again.
  retry: (_, _) => null,
);

/// This phone is only bonded while the car has a validated phone, so the device
/// refuses it the approval and removing a validated phone.
bool isOutrankedByValidatedPhone(PhoneAccessState access) =>
    access.trust == PhoneTrustLevel.PHONE_TRUST_LEVEL_BONDED &&
    access.carHasValidatedPhone;
