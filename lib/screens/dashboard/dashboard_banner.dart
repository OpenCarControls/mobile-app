import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/providers/ble_connection_provider.dart';
import 'package:open_car_app/providers/can_access_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/phone_access_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/screens/help_screen.dart';
import 'package:open_car_app/screens/phone_validation_screen.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/can_read_write_approval_dialog.dart';

/// The one banner slot at the top of the tile area. Only the most important
/// banner shows: a wrong vehicle platform, then a lost Bluetooth bond, then
/// control that isn't approved, then a phone that isn't validated. See
/// "Banners" in `docs/ui.md`.
class DashboardBannerSlot extends ConsumerWidget {
  const DashboardBannerSlot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mismatchedId = ref.watch(
      vehicleStateProvider.select((s) => s.mismatchedPlatformId),
    );
    final bondLost = ref.watch(bleBondLostProvider);
    // Only known over Bluetooth: null otherwise.
    final access = ref.watch(canAccessStateProvider);
    final trust = ref.watch(phoneAccessStateProvider.select((a) => a?.trust));

    final Widget? banner;
    if (mismatchedId != null) {
      final hexId = mismatchedId
          .toRadixString(16)
          .toUpperCase()
          .padLeft(8, '0');
      banner = DashboardBanner(
        icon: Symbols.warning,
        title: 'Wrong vehicle platform',
        text:
            'The device reports a different vehicle platform (0x$hexId) than '
            'the one paired. Its updates are ignored until you pair again.',
        actions: [
          (
            label: 'Unpair',
            onPressed: () => ref.read(pairedVehicleProvider.notifier).unpair(),
          ),
        ],
      );
    } else if (bondLost) {
      banner = DashboardBanner(
        icon: Symbols.bluetooth_disabled,
        title: 'The device no longer knows this phone',
        text:
            'It keeps dropping the connection. Forget the OpenCar device in '
            "Android's Bluetooth settings, put the device in pairing mode, then "
            'pair again.',
        actions: [
          (label: 'Help', onPressed: () => HelpScreen.open(context)),
          (
            label: 'Unpair and pair again',
            onPressed: () => ref.read(pairedVehicleProvider.notifier).unpair(),
          ),
        ],
      );
    } else if (access != null && canAccessNeedsApproval(access)) {
      final otherCar =
          access.approval ==
          CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_OTHER_CAR;
      banner = DashboardBanner(
        icon: Symbols.lock,
        title: "Control isn't approved",
        text: otherCar
            ? 'Control was approved for a different car. The device only '
                  'listens to this one until you approve it.'
            : 'The device only listens to the car. Approve control to send '
                  'commands to it.',
        actions: [
          (
            label: 'Review',
            onPressed: () => showCanReadWriteApprovalDialog(context),
          ),
        ],
      );
    } else if (trust == PhoneTrustLevel.PHONE_TRUST_LEVEL_BONDED) {
      banner = DashboardBanner(
        icon: Symbols.verified_user,
        title: 'Validate this phone',
        text:
            'Only a validated phone can send commands and see the full '
            'dashboard. Validating takes a moment in the car.',
        actions: [
          (
            label: 'Validate',
            onPressed: () => PhoneValidationScreen.open(context),
          ),
        ],
      );
    } else {
      banner = null;
    }

    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: banner == null
          ? const SizedBox(width: double.infinity)
          : Padding(padding: const EdgeInsets.only(bottom: 8), child: banner),
    );
  }
}

/// A banner action: a label and what it does.
typedef DashboardBannerAction = ({String label, VoidCallback onPressed});

/// A banner in the accent container colours: an icon, a title, one sentence
/// and its actions.
class DashboardBanner extends StatelessWidget {
  const DashboardBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String text;
  final List<DashboardBannerAction> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final foreground = tokens.onAccentContainer;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        decoration: ShapeDecoration(
          color: tokens.accentContainer,
          shape: tokens.radiusMedium.shape(),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Icon(icon, color: foreground, size: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.buttonTitle.copyWith(
                          color: foreground,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        text,
                        style: AppTextStyles.caption.copyWith(
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                children: [
                  for (final action in actions)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: foreground),
                      onPressed: action.onPressed,
                      child: Text(action.label),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
