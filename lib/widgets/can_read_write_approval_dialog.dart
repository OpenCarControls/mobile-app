import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/providers/can_access_provider.dart';

/// Asks the owner to approve CAN read-write mode for the car the device is
/// plugged into, after showing what it risks. Approving needs the
/// acknowledgement ticked. Sends the approval and reports the device's answer.
Future<void> showCanReadWriteApprovalDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _CanReadWriteApprovalDialog(),
  );
}

class _CanReadWriteApprovalDialog extends ConsumerStatefulWidget {
  const _CanReadWriteApprovalDialog();

  @override
  ConsumerState<_CanReadWriteApprovalDialog> createState() =>
      _CanReadWriteApprovalDialogState();
}

class _CanReadWriteApprovalDialogState
    extends ConsumerState<_CanReadWriteApprovalDialog> {
  bool _acknowledged = false;
  bool _sending = false;
  String? _error;

  Future<void> _approve() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(canAccessActionsProvider).setApproval(true);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.warning_amber, color: theme.colorScheme.error),
      title: const Text('Allow control of this car?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Until now the device has only listened to the car. Allowing '
              'control lets it send messages on the car\'s internal network '
              'to carry out commands.',
            ),
            const SizedBox(height: 12),
            const Text(
              'This is experimental software, not made or approved by the '
              'car\'s manufacturer. A wrong or unexpected message can make '
              'the car behave unexpectedly, show warnings, drain its battery '
              'or need a visit to a workshop, and may affect your warranty. '
              'Only send commands while you can see the car and it is parked '
              'safely.',
            ),
            const SizedBox(height: 12),
            const Text(
              'This approval is only for the car the device is plugged into '
              'now. Moving the device to another car needs a new approval. '
              'You can withdraw it at any time.',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _acknowledged,
              onChanged: _sending
                  ? null
                  : (v) => setState(() => _acknowledged = v ?? false),
              title: const Text('I understand the risks'),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: _acknowledged && !_sending ? _approve : null,
          child: const Text('Allow control'),
        ),
      ],
    );
  }
}
