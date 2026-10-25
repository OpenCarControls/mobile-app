import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/can_access_provider.dart';
import 'package:open_car_app/widgets/can_read_write_approval_dialog.dart';

/// Shown when the device has identified the car but the owner hasn't approved
/// control of it (never, or only for another car). Opens the approval dialog.
class CanAccessBanner extends ConsumerWidget {
  const CanAccessBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(canAccessStateProvider);
    if (state == null || !canAccessNeedsApproval(state)) {
      return const SizedBox.shrink();
    }

    final otherCar =
        state.approval ==
        CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_OTHER_CAR;
    return MaterialBanner(
      leading: const Icon(Icons.lock_outline),
      content: Text(
        otherCar
            ? 'Control was approved for a different car. The device only '
                  'listens to this one until you approve it.'
            : 'The device only listens to the car. Approve control to send '
                  'commands to it.',
      ),
      actions: [
        TextButton(
          onPressed: () => showCanReadWriteApprovalDialog(context),
          child: const Text('Review'),
        ),
      ],
    );
  }
}
