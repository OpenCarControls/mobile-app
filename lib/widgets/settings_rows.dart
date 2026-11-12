import 'package:material_ui/material_ui.dart';

import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';

/// Rows are at least this high.
const double kSettingsRowMinHeight = 56;

/// The heading above a card of rows on the settings screens.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: AppTextStyles.caption.copyWith(
            color: context.tokens.textSecondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

/// A card of rows, with a divider between them.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface,
      shape: tokens.radiusMedium.shape(side: BorderSide(color: tokens.outline)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0)
              Divider(height: 1, thickness: 1, color: tokens.outline),
            child,
          ],
        ],
      ),
    );
  }
}

/// One row of a [SettingsCard]: a title, an optional line under it, an optional
/// value on the right, and a chevron when tapping it opens something.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.opensScreen = false,
    this.danger = false,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;

  /// Shows the chevron.
  final bool opensScreen;

  /// A destructive action: the title uses the danger colour.
  final bool danger;

  /// Greys the row out and ignores taps.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final value = this.value;
    return ListTile(
      minTileHeight: kSettingsRowMinHeight,
      enabled: enabled,
      onTap: onTap,
      title: Text(
        title,
        style: danger && enabled ? TextStyle(color: tokens.danger) : null,
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: value == null && !opensScreen
          ? null
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  if (value != null)
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  if (opensScreen)
                    ExcludeSemantics(
                      child: Icon(
                        Icons.chevron_right,
                        color: enabled ? tokens.textSecondary : tokens.outline,
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// A row with its control under the title: the segmented choices.
class SettingsControlRow extends StatelessWidget {
  const SettingsControlRow({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyLarge),
          child,
        ],
      ),
    );
  }
}

/// Asks before an action, and completes with whether the user confirmed.
Future<bool> confirmSettingsAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool danger = false,
}) async {
  final tokens = context.tokens;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: tokens.danger,
                  foregroundColor: tokens.onDanger,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return confirmed == true;
}
