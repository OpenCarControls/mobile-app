import 'package:flutter/widgets.dart';

/// How strongly values from a past snapshot are drawn.
const double kStaleOpacity = 0.5;

/// Marks the values below it as coming from a past snapshot, so they never
/// look live (see "States and edge cases" in `docs/ui.md`). Tile surfaces and
/// the header dim what they show while [stale].
class StaleValues extends InheritedWidget {
  const StaleValues({super.key, required this.stale, required super.child});

  final bool stale;

  /// Whether the values at [context] are stale. False without a [StaleValues]
  /// above it.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StaleValues>()?.stale ?? false;

  @override
  bool updateShouldNotify(StaleValues oldWidget) => stale != oldWidget.stale;
}

/// Dims [child] while the values at its place are stale.
class StaleDimmed extends StatelessWidget {
  const StaleDimmed({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: StaleValues.of(context) ? kStaleOpacity : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      child: child,
    );
  }
}
