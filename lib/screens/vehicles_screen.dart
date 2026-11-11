import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_list_provider.dart';
import 'package:open_car_app/screens/pairing_wizard_screen.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/widgets/dashed_outline.dart';
import 'package:open_car_app/widgets/settings_rows.dart';
import 'package:open_car_app/widgets/vehicle_list_parts.dart';

/// The paired vehicles: switch to one, rename or unpair it, or add another.
/// See "Managing" under "Vehicles" in `docs/ui-screens.md`.
class VehiclesScreen extends ConsumerWidget {
  const VehiclesScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const VehiclesScreen());

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(route());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final vehicles = ref.watch(vehicleListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicles')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          for (final entry in vehicles) ...[
            _VehicleCard(entry: entry),
            const SizedBox(height: 10),
          ],
          _AddVehicleTile(
            onTap: () => Navigator.of(
              context,
            ).push(PairingWizardScreen.addVehicleRoute()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
            child: Text(
              'Only the current vehicle connects over Bluetooth. The others '
              'show their last known state.',
              style: AppTextStyles.caption.copyWith(
                color: tokens.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleCard extends ConsumerWidget {
  const _VehicleCard({required this.entry});

  final VehicleListEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final status = vehicleStatusText(ref, entry);
    final secondary = AppTextStyles.caption.copyWith(
      color: tokens.textSecondary,
    );
    final definition = entry.definition;
    final summary = Semantics(
      button: !entry.current,
      selected: entry.current,
      label: entry.current
          ? '${entry.name}, current vehicle'
          : 'Switch to ${entry.name}',
      value: [?definition?.platformLabel, status].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: entry.current
            ? null
            : () => unawaited(
                ref
                    .read(pairedVehiclesProvider.notifier)
                    .switchTo(entry.config.id),
              ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            spacing: 14,
            children: [
              VehicleAvatar(skin: definition?.skin ?? defaultSkin, size: 48),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.name, style: AppTextStyles.statValue),
                    if (definition != null)
                      Text(definition.platformLabel, style: secondary),
                    const SizedBox(height: 3),
                    Text(status, style: secondary),
                  ],
                ),
              ),
              if (entry.current)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: ShapeDecoration(
                    color: tokens.accentContainer,
                    shape: tokens.radiusPill.shape(),
                  ),
                  child: Text(
                    'Current',
                    style: AppTextStyles.caption.copyWith(
                      color: tokens.onAccentContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    Widget action(String label, VoidCallback onPressed, {Color? color}) =>
        Expanded(
          child: Semantics(
            label: '$label ${entry.name}',
            excludeSemantics: true,
            button: true,
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: color ?? tokens.text,
                shape: const RoundedRectangleBorder(),
              ),
              onPressed: onPressed,
              child: Text(label),
            ),
          ),
        );

    return Material(
      color: tokens.surface,
      shape: tokens.radiusMedium.shape(side: BorderSide(color: tokens.outline)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summary,
          Divider(height: 1, thickness: 1, color: tokens.outline),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                action('Rename', () => _rename(context, ref)),
                VerticalDivider(width: 1, thickness: 1, color: tokens.outline),
                action(
                  'Unpair',
                  () => _unpair(context, ref),
                  color: tokens.danger,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(
        name: entry.config.name ?? '',
        platformName: entry.definition?.displayName ?? entry.name,
      ),
    );
    if (name == null) return;
    await ref
        .read(pairedVehiclesProvider.notifier)
        .rename(entry.config.id, name);
  }

  Future<void> _unpair(BuildContext context, WidgetRef ref) async {
    final others = ref.read(pairedVehiclesProvider).vehicles.length > 1;
    final confirmed = await confirmUnpair(
      context,
      name: entry.name,
      othersRemain: others,
    );
    if (!confirmed || !context.mounted) return;
    // With none left, the router shows the wizard under these screens.
    if (!others) Navigator.of(context).popUntil((route) => route.isFirst);
    await ref.read(pairedVehiclesProvider.notifier).unpair(entry.config.id);
  }
}

/// Asks before unpairing the vehicle called [name], and completes with
/// whether the user confirmed. [othersRemain] is whether other vehicles stay
/// paired. See "Unpairing" in `docs/ui-screens.md`.
Future<bool> confirmUnpair(
  BuildContext context, {
  required String name,
  required bool othersRemain,
}) => confirmSettingsAction(
  context,
  title: 'Unpair $name?',
  message: [
    '$name will be removed from this app. To use it again, put the device '
        'in pairing mode and pair again.',
    if (othersRemain) 'Your other vehicles are not affected.',
  ].join('\n\n'),
  action: 'Unpair',
  danger: true,
);

/// Asks for a vehicle's new name. A blank one goes back to [platformName].
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name, required this.platformName});

  /// The name the user gave it, or empty.
  final String name;
  final String platformName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename vehicle'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 30,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: 'Name',
          hintText: widget.platformName,
          helperText: 'Leave empty to use ${widget.platformName}',
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _AddVehicleTile extends StatelessWidget {
  const _AddVehicleTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final shape = tokens.radiusMedium.shape();
    return CustomPaint(
      painter: DashedOutlinePainter(shape: shape, color: tokens.textSecondary),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 10,
              children: [
                Icon(Symbols.add, color: tokens.textSecondary),
                Text(
                  'Add a vehicle',
                  style: AppTextStyles.buttonTitle.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
