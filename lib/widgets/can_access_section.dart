import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/can_access_provider.dart';
import 'package:open_car_app/providers/phone_access_provider.dart';
import 'package:open_car_app/screens/phone_validation_screen.dart';
import 'package:open_car_app/widgets/can_read_write_approval_dialog.dart';
import 'package:open_car_app/widgets/settings_rows.dart';

/// Why the approval controls are off for a phone that isn't validated.
const _needsValidatedPhone =
    'Only a validated phone can change this once a phone is validated in this '
    'car.';

/// The Car access card of the settings: whether the device may send commands
/// to the car and why not, approving or withdrawing control, this phone's
/// trust, and the developer write lock in development firmware builds. Needs a
/// Bluetooth connection; shows a hint otherwise.
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
    final confirmed = await confirmSettingsAction(
      context,
      title: 'Withdraw control?',
      message:
          'The device goes back to only listening to the car, and you will '
          'have to approve control again to send commands.',
      action: 'Withdraw',
    );
    if (confirmed) await _run((a) => a.setApproval(false));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(canAccessStateProvider);
    if (state == null) {
      return const SettingsCard(
        children: [
          SettingsRow(
            title: 'Vehicle control',
            subtitle: 'Connect over Bluetooth to see or change it.',
          ),
        ],
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

    final access = ref.watch(phoneAccessStateProvider);
    final locked = access != null && isOutrankedByValidatedPhone(access);
    final thisPhone = switch (access?.trust) {
      PhoneTrustLevel.PHONE_TRUST_LEVEL_VALIDATED => 'Validated',
      PhoneTrustLevel.PHONE_TRUST_LEVEL_BONDED => 'Not validated',
      _ => null,
    };

    return SettingsCard(
      children: [
        SettingsRow(
          title: 'Vehicle control',
          subtitle: canAccessSummary(state),
        ),
        if (canAccessNeedsApproval(state))
          SettingsRow(
            title: 'Approve control of this car',
            subtitle: locked ? _needsValidatedPhone : null,
            opensScreen: true,
            enabled: !_sending && !locked,
            onTap: () => showCanReadWriteApprovalDialog(context),
          ),
        // Styled as an action, so it isn't read as a heading.
        if (hasApproval)
          SettingsRow(
            title: 'Withdraw control approval',
            subtitle: locked
                ? _needsValidatedPhone
                : 'The device goes back to only listening.',
            danger: true,
            opensScreen: true,
            enabled: !_sending && !locked,
            onTap: _confirmWithdraw,
          ),
        if (thisPhone != null)
          SettingsRow(title: 'This phone', value: thisPhone),
        if (access?.trust == PhoneTrustLevel.PHONE_TRUST_LEVEL_BONDED)
          SettingsRow(
            title: 'Validate this phone',
            opensScreen: true,
            onTap: () => PhoneValidationScreen.open(context),
          ),
        // Development firmware only: an extra lock, locked at every boot.
        if (state.devLockAvailable)
          SwitchListTile(
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
