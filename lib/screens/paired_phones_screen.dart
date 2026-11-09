import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/models/paired_phone.dart';
import 'package:open_car_app/providers/phone_access_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/screens/phone_validation_screen.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/settings_rows.dart';

/// The phones paired with the device, in the order they were paired. See
/// "Paired phones" in `docs/ui-screens.md`.
class PairedPhonesScreen extends ConsumerStatefulWidget {
  const PairedPhonesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PairedPhonesScreen()));

  @override
  ConsumerState<PairedPhonesScreen> createState() => _PairedPhonesScreenState();
}

class _PairedPhonesScreenState extends ConsumerState<PairedPhonesScreen> {
  bool _removing = false;

  Future<void> _remove(PairedPhoneInfo phone) async {
    final confirmed = await confirmSettingsAction(
      context,
      title: 'Remove this phone?',
      message:
          "It can no longer connect over Bluetooth until it's paired again.",
      action: 'Remove',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _removing = true);
    try {
      await ref
          .read(phoneValidationActionsProvider)
          .removePairedPhone(phone.deviceId);
      ref.invalidate(pairedPhonesProvider);
      final phones = await ref.read(pairedPhonesProvider.future);
      final kept = phones.any((p) => listEquals(p.deviceId, phone.deviceId));
      if (kept) {
        _showMessage(
          'The device kept this phone. It can only remove phones while it '
          'is in pairing mode (see Help).',
        );
      }
    } catch (e) {
      _showMessage('$e');
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final phones = ref.watch(pairedPhonesProvider);
    final access = ref.watch(phoneAccessStateProvider);
    final outranked = access != null && isOutrankedByValidatedPhone(access);
    final name = ref.watch(selectedVehicleProvider)?.displayName ?? 'the car';
    final note = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary);

    return Scaffold(
      appBar: AppBar(title: const Text('Paired phones')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            'Phones paired with the device in $name, in the order they were '
            'paired. Only a validated phone can send commands to the car.',
            style: note,
          ),
          const SizedBox(height: 16),
          switch (phones) {
            AsyncValue(:final value?) => SettingsCard(
              children: [
                for (final phone in value)
                  _PhoneRow(
                    phone: phone,
                    onRemove: _removing ? null : () => _remove(phone),
                    protected: phone.isValidated && outranked,
                  ),
              ],
            ),
            AsyncValue(hasError: true) => SettingsCard(
              children: [
                SettingsRow(
                  title: "Couldn't read the phones from the device",
                  subtitle: 'Tap to try again.',
                  onTap: () => ref.invalidate(pairedPhonesProvider),
                ),
              ],
            ),
            _ => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          },
          const SizedBox(height: 16),
          Text(
            "The device doesn't know phone names; the app only knows which "
            'one is this phone. Once a phone is validated in $name, only a '
            'validated phone can remove it or change the vehicle control '
            'approval.',
            style: AppTextStyles.caption.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({
    required this.phone,
    required this.onRemove,
    required this.protected,
  });

  final PairedPhoneInfo phone;
  final VoidCallback? onRemove;

  /// The device would refuse to remove it from this phone.
  final bool protected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final note = switch ((phone.isThisPhone, phone.isValidated, protected)) {
      (true, false, _) => "This phone can't send commands yet.",
      (false, _, true) =>
        'Only a validated phone can remove a validated '
            'phone.',
      _ => null,
    };
    final removable = !phone.isThisPhone;
    final validatable = phone.isThisPhone && !phone.isValidated;
    final noteStyle = AppTextStyles.caption.copyWith(
      color: tokens.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 12,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: ShapeDecoration(
                  color: phone.isValidated
                      ? tokens.accentContainer
                      : tokens.outline,
                  shape: tokens.radiusRound.shape(),
                ),
                child: Icon(
                  Symbols.smartphone,
                  color: phone.isValidated
                      ? tokens.onAccentContainer
                      : tokens.textSecondary,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      phone.isThisPhone ? 'This phone' : 'Another phone',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text('ID …${_idEnd(phone.deviceId)}', style: noteStyle),
                  ],
                ),
              ),
              _TrustChip(validated: phone.isValidated),
            ],
          ),
          if (note != null || removable)
            Row(
              spacing: 12,
              children: [
                Expanded(child: Text(note ?? '', style: noteStyle)),
                if (validatable)
                  FilledButton(
                    onPressed: () => PhoneValidationScreen.open(context),
                    child: const Text('Validate'),
                  ),
                if (removable)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.danger,
                    ),
                    onPressed: protected ? null : onRemove,
                    child: const Text('Remove'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// The last two bytes of the id, which tell phones apart at a glance.
  static String _idEnd(List<int> id) => id.reversed
      .take(2)
      .toList()
      .reversed
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.validated});

  final bool validated;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: ShapeDecoration(
        color: validated ? tokens.accentContainer : null,
        shape: tokens.radiusPill.shape(
          side: validated ? BorderSide.none : BorderSide(color: tokens.outline),
        ),
      ),
      child: Text(
        validated ? 'Validated' : 'Not validated',
        style: AppTextStyles.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: validated ? tokens.onAccentContainer : tokens.textSecondary,
        ),
      ),
    );
  }
}
