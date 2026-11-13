import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_list_provider.dart';
import 'package:open_car_app/screens/pairing_wizard_screen.dart';
import 'package:open_car_app/screens/vehicles_screen.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/widgets/dashed_outline.dart';
import 'package:open_car_app/widgets/popover_arrow.dart';
import 'package:open_car_app/widgets/vehicle_list_parts.dart';

const _gutter = 12.0;
const _maxWidth = 360.0;
const _arrowWidth = 20.0;
const _arrowHeight = 10.0;

/// How far the arrow's tip stays from the popover's corners.
const _arrowInset = 24.0;

/// The empty space below the name inside its touch target.
const _nameSlack = 4.0;

/// Where the vehicle name is on the screen. The name keeps this current,
/// because it moves when the dashboard changes layout with the popover open.
class _NamePosition extends Notifier<Rect?> {
  @override
  Rect? build() => null;

  void set(Rect position) {
    if (position != state) state = position;
  }
}

final _namePositionProvider = NotifierProvider<_NamePosition, Rect?>(
  _NamePosition.new,
);

/// Records where the vehicle name whose context is [name] is. Call after
/// layout.
void reportVehicleNamePosition(BuildContext name, WidgetRef ref) {
  final box = name.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return;
  ref
      .read(_namePositionProvider.notifier)
      .set(box.localToGlobal(Offset.zero) & box.size);
}

/// Opens the vehicle switcher, anchored to the vehicle name whose context is
/// [name]. See "Vehicles" in `docs/ui-screens.md`.
Future<void> showVehicleSwitcher(BuildContext name, WidgetRef ref) {
  reportVehicleNamePosition(name, ref);
  return showGeneralDialog<void>(
    context: name,
    barrierDismissible: true,
    barrierLabel: 'Close vehicles',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (_, _, _) => const _Popover(),
  );
}

class _Popover extends ConsumerWidget {
  const _Popover();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anchor = ref.watch(_namePositionProvider);
    if (anchor == null) return const SizedBox.shrink();
    final tokens = context.tokens;
    final size = MediaQuery.sizeOf(context);
    final width = math.min(size.width - 2 * _gutter, _maxWidth);
    final left = (anchor.left - _gutter).clamp(
      _gutter,
      size.width - width - _gutter,
    );
    final top = anchor.bottom - _nameSlack + _arrowHeight;
    final maxHeight =
        size.height - top - MediaQuery.paddingOf(context).bottom - _gutter;
    // Under the name, but never past the popover's rounded corners.
    final arrowX = anchor.center.dx.clamp(
      left + _arrowInset,
      left + width - _arrowInset,
    );
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: 'Vehicles',
              child: Material(
                color: tokens.surface,
                clipBehavior: Clip.antiAlias,
                shape: tokens.radiusLarge.shape(
                  side: BorderSide(color: tokens.outline),
                ),
                child: const _Content(),
              ),
            ),
          ),
        ),
        Positioned(
          left: arrowX - _arrowWidth / 2,
          // One pixel into the card, to cover its border.
          top: top - _arrowHeight + 1,
          child: ExcludeSemantics(
            child: CustomPaint(
              size: const Size(_arrowWidth, _arrowHeight),
              painter: PopoverArrowPainter(
                fill: tokens.surface,
                border: tokens.outline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final vehicles = ref.watch(vehicleListProvider);
    // The popover's navigator is the app's, where the screens it opens go.
    final navigator = Navigator.of(context);

    void switchTo(VehicleListEntry entry) {
      navigator.pop();
      if (!entry.current) {
        unawaited(
          ref.read(pairedVehiclesProvider.notifier).switchTo(entry.config.id),
        );
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(top: 6),
            children: [
              for (final entry in vehicles)
                _VehicleRow(entry: entry, onTap: () => switchTo(entry)),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.outline),
        const SizedBox(height: 4),
        _AddVehicleRow(
          onTap: () {
            navigator.pop();
            unawaited(navigator.push(PairingWizardScreen.addVehicleRoute()));
          },
        ),
        InkWell(
          onTap: () {
            navigator.pop();
            unawaited(navigator.push(VehiclesScreen.route()));
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Manage vehicles',
                      style: AppTextStyles.buttonTitle.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  ExcludeSemantics(
                    child: Icon(
                      Symbols.chevron_right,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _VehicleRow extends ConsumerWidget {
  const _VehicleRow({required this.entry, required this.onTap});

  final VehicleListEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final status = vehicleStatusText(ref, entry);
    return Semantics(
      button: true,
      selected: entry.current,
      label: entry.current
          ? '${entry.name}, current vehicle'
          : 'Switch to ${entry.name}',
      value: status,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              spacing: 12,
              children: [
                VehicleAvatar(skin: entry.definition?.skin ?? defaultSkin),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.buttonTitle.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        status,
                        style: AppTextStyles.caption.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.current)
                  Icon(Symbols.check, color: tokens.accent, weight: 600),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddVehicleRow extends StatelessWidget {
  const _AddVehicleRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            spacing: 12,
            children: [
              ExcludeSemantics(
                child: CustomPaint(
                  painter: DashedOutlinePainter(
                    shape: const CircleBorder(),
                    color: tokens.textSecondary,
                  ),
                  child: SizedBox.square(
                    dimension: 44,
                    child: Icon(Symbols.add, color: tokens.textSecondary),
                  ),
                ),
              ),
              Expanded(
                child: Text('Add a vehicle', style: AppTextStyles.buttonTitle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
