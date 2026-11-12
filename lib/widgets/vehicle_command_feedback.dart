import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/models/connection_activity.dart';
import 'package:open_car_app/providers/can_access_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/connection_activity_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/screens/phone_validation_screen.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/can_read_write_approval_dialog.dart';

/// Sends a vehicle command and, if it fails, says why in a SnackBar: the
/// device's reason (e.g. it only listens to the car until control is
/// approved), that this phone needs validating in the car, a timeout, or the
/// transport's error. Records what came of it in the connection activity, as
/// [activityName]. Returns whether it was sent and accepted.
Future<bool> sendVehicleCommand(
  BuildContext context,
  WidgetRef ref,
  Future<Object?> Function() send, {
  required String activityName,
}) async {
  // Read now: the control may be gone by the time the vehicle answers.
  final log = ref.read(connectionActivityLogsProvider.notifier);
  final remote = ref.read(transportTypeProvider) == TransportType.mqtt;
  final needsApproval = commandNeedsApproval(ref);
  try {
    await send();
    log.recordCommand(activityName, CommandOutcome.done, sentRemotely: remote);
    return true;
  } catch (e) {
    log.recordCommand(
      activityName,
      commandOutcomeOf(e, needsApproval: needsApproval),
      // A transport error means it never left the phone.
      sentRemotely: remote && e is! CarTransportException,
    );
    if (context.mounted) {
      showVehicleCommandMessage(
        context,
        ref,
        vehicleCommandErrorText(e),
        offerValidation: e is CommandRejectedException && e.needsValidation,
      );
    }
    return false;
  }
}

/// Whether control of the car still needs approving.
bool commandNeedsApproval(WidgetRef ref) {
  final access = ref.read(canAccessStateProvider);
  return access != null && canAccessNeedsApproval(access);
}

/// What the connection activity says about a command that failed with [error].
/// [needsApproval] tells a device refusing because control isn't approved from
/// one refusing for any other reason.
CommandOutcome commandOutcomeOf(Object error, {required bool needsApproval}) =>
    switch (error) {
      CommandRejectedException(needsValidation: true) =>
        CommandOutcome.notValidated,
      CommandRejectedException(:final response)
          when response.statusCode ==
              CommandStatusCode.COMMAND_STATUS_CODE_REJECTED_UNAVAILABLE =>
        needsApproval
            ? CommandOutcome.needsApproval
            : CommandOutcome.vehicleUnavailable,
      TimeoutException() => CommandOutcome.noAnswer,
      CarTransportException() => CommandOutcome.vehicleUnavailable,
      _ => CommandOutcome.failed,
    };

/// Shows [text] about a vehicle command in a SnackBar. When control of the car
/// still needs approving, the SnackBar opens the approval dialog. Otherwise,
/// with [offerValidation], it opens the phone validation.
void showVehicleCommandMessage(
  BuildContext context,
  WidgetRef ref,
  String text, {
  bool offerValidation = false,
}) {
  final access = ref.read(canAccessStateProvider);
  final canApprove = access != null && canAccessNeedsApproval(access);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(text),
      action: canApprove
          ? SnackBarAction(
              label: 'Review',
              onPressed: () => showCanReadWriteApprovalDialog(context),
            )
          : offerValidation
          ? SnackBarAction(
              label: 'Validate',
              onPressed: () => PhoneValidationScreen.open(context),
            )
          : null,
    ),
  );
}

/// The text shown for a failed vehicle command.
String vehicleCommandErrorText(Object error) {
  final text = switch (error) {
    CommandRejectedException(needsValidation: true) =>
      'This phone needs validating in the car before it can send commands.',
    TimeoutException() => 'The vehicle did not answer the command.',
    CarTransportException(:final message) => message,
    // The device's CommandResponse.error_message.
    _ => '$error',
  };
  if (text.isEmpty) return 'Command failed';
  return text[0].toUpperCase() + text.substring(1);
}
