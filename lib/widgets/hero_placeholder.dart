import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/theme/app_tokens.dart';

/// Stands in for the vehicle's hero until it is built (see `docs/ui-hero.md`):
/// a car glyph centred in its box and scaled to fit it.
class HeroPlaceholder extends StatelessWidget {
  const HeroPlaceholder({super.key, this.dimmed = false});

  /// For stale state.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          return Center(
            child: Icon(
              Symbols.directions_car,
              size: side.isFinite ? side * 0.8 : 96,
              color: dimmed ? tokens.outline : tokens.textSecondary,
            ),
          );
        },
      ),
    );
  }
}
