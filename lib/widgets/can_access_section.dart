import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/can_access_provider.dart';
import 'package:open_car_app/widgets/can_read_write_approval_dialog.dart';

/// Vehicle control settings, for a settings or developer section: whether the
/// device may send commands to the car and why not, approving or withdrawing
/// control, and the developer write lock in development firmware builds.
/// Needs a Bluetooth connection; shows a hint otherwise.
class CanAccessSection extends ConsumerStatefulWidget {
  const CanAccessSection({super.key});

  @override
  ConsumerState<CanAccessSection> createState() => _CanAccessSectionState();
}

class _CanAccessSectionState extends ConsumerState<CanAccessSection> {
  bool _sending = false;

  Future<void> _run(Future<void> Function(CanAccessActions) action) async {
    setState(() => _sending = true);
    try {
      await action(ref.read(canAccessActionsProvider));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirmWithdraw() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw control?'),
        content: const Text(
          'The device goes back to only listening to the car, and you will '
          'have to approve control again to send commands.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run((a) => a.setApproval(false));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(canAccessStateProvider);
    if (state == null) {
      return const ListTile(
        leading: Icon(Icons.lock_outline),
        title: Text('Vehicle control'),
        subtitle: Text('Connect over Bluetooth to see or change it.'),
      );
    }

    final approved =
        state.approval == CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_APPROVED;
    final hasApproval =
        approved ||
        state.approval ==
            CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_OTHER_CAR ||
        state.approval ==
            CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_AWAITING_CAR;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: Icon(state.readOnly ? Icons.lock_outline : Icons.lock_open),
          title: const Text('Vehicle control'),
          subtitle: Text(canAccessSummary(state)),
        ),
        if (canAccessNeedsApproval(state))
          ListTile(
            title: const Text('Approve control of this car'),
            trailing: const Icon(Icons.chevron_right),
            enabled: !_sending,
            onTap: () => showCanReadWriteApprovalDialog(context),
          ),
        if (hasApproval)
          ListTile(
            title: const Text('Withdraw control approval'),
            enabled: !_sending,
            onTap: _confirmWithdraw,
          ),
        // Development firmware only: an extra lock, locked at every boot.
        if (state.devLockAvailable)
          SwitchListTile(
            secondary: const Icon(Icons.developer_mode),
            title: const Text('Developer write lock unlocked'),
            subtitle: const Text(
              'Development firmware only. Locks again at every restart.',
            ),
            value: state.devUnlocked,
            onChanged: _sending
                ? null
                : (unlocked) => _run((a) => a.setDevWriteUnlocked(unlocked)),
          ),
      ],
    );
  }
}
