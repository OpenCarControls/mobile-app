import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/providers/can_access_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/widgets/can_read_write_approval_dialog.dart';

/// Sends a vehicle command and, if it fails, says why in a SnackBar: the
/// device's reason (e.g. it only listens to the car until control is
/// approved), a timeout, or the transport's error. When control of the car
/// still needs approving, the SnackBar opens the approval dialog.
Future<void> sendVehicleCommand(
  BuildContext context,
  WidgetRef ref,
  Future<Object?> Function() send,
) async {
  try {
    await send();
  } catch (e) {
    if (!context.mounted) return;
    final access = ref.read(canAccessStateProvider);
    final canApprove = access != null && canAccessNeedsApproval(access);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(vehicleCommandErrorText(e)),
        action: canApprove
            ? SnackBarAction(
                label: 'Review',
                onPressed: () => showCanReadWriteApprovalDialog(context),
              )
            : null,
      ),
    );
  }
}

/// The text shown for a failed vehicle command.
String vehicleCommandErrorText(Object error) {
  final text = switch (error) {
    TimeoutException() => 'The vehicle did not answer the command.',
    CarTransportException(:final message) => message,
    // The device's CommandResponse.error_message.
    _ => '$error',
  };
  if (text.isEmpty) return 'Command failed';
  return text[0].toUpperCase() + text.substring(1);
}
