import 'package:material_ui/material_ui.dart';

import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/stale_values.dart';

/// The look shared by all tiles: a translucent fill with a hairline border, or
/// the accent container fill when [on]. Under a stale [StaleValues], the
/// content and the fill are dimmed.
///
/// It has no blur of its own. The surface behind the tiles carries the one
/// `BackdropFilter` (see `docs/ui-theming.md`).
class TileSurface extends StatelessWidget {
  const TileSurface({
    super.key,
    required this.child,
    this.on = false,
    this.padding = const EdgeInsets.all(10),
  });

  final Widget child;
  final bool on;
  final EdgeInsetsGeometry padding;

  /// The "on" fill's opacity over what's behind it.
  static const _onOpacity = 0.9;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final stale = StaleValues.of(context);
    final foreground = on ? tokens.onAccentContainer : tokens.text;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: on
            ? tokens.accentContainer.withValues(
                alpha: stale ? _onOpacity * kStaleOpacity : _onOpacity,
              )
            : tokens.glassFill,
        shape: tokens.radiusMedium.shape(
          side: BorderSide(color: tokens.tileBorder),
        ),
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: foreground),
        child: DefaultTextStyle.merge(
          style: AppTextStyles.caption.copyWith(color: foreground),
          child: StaleDimmed(child: child),
        ),
      ),
    );
  }
}
