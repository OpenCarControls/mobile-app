import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';

/// The stages shown on the wizard's progress bar.
enum WizardStage {
  find('Find your vehicle'),
  pair('Pair'),
  setUp('Set up');

  const WizardStage(this.label);

  final String label;

  String get stepLabel =>
      'Step ${index + 1} of ${WizardStage.values.length} · $label';
}

/// One page of the wizard: the heading with Help, the progress bar, the step's
/// content in the middle and full-width buttons at the bottom.
///
/// The content scrolls when it doesn't fit, so long text and a large font size
/// never push the buttons off the screen.
class WizardFrame extends StatelessWidget {
  const WizardFrame({
    super.key,
    required this.heading,
    required this.stage,
    required this.onHelp,
    required this.title,
    this.onClose,
    this.medallion,
    this.body,
    this.content = const [],
    this.actions = const [],
  });

  final String heading;
  final WizardStage stage;
  final VoidCallback onHelp;

  /// Shows a close button when set.
  final VoidCallback? onClose;

  final Widget? medallion;
  final String title;
  final String? body;

  /// Shown under [body], full width.
  final List<Widget> content;

  /// The buttons at the bottom, top to bottom.
  final List<Widget> actions;

  /// The buttons' area keeps this height, so the content doesn't move between
  /// steps with one button and steps with two.
  static const double _actionsMinHeight = 114;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(heading: heading, onClose: onClose, onHelp: onHelp),
              const SizedBox(height: 12),
              _ProgressBar(stage: stage),
              const SizedBox(height: 8),
              Text(
                stage.stepLabel,
                style: AppTextStyles.caption.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _content(tokens),
                      ),
                    ),
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _actionsMinHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: actions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(AppTokens tokens) {
    final body = this.body;
    return [
      const SizedBox(height: 16),
      if (medallion != null) ...[
        Center(child: medallion),
        const SizedBox(height: 8),
      ],
      Semantics(
        header: true,
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: AppTextStyles.wizardTitle,
        ),
      ),
      if (body != null) ...[
        const SizedBox(height: 16),
        Text(
          body,
          textAlign: TextAlign.center,
          style: AppTextStyles.wizardBody.copyWith(color: tokens.textSecondary),
        ),
      ],
      for (final widget in content) ...[const SizedBox(height: 16), widget],
      const SizedBox(height: 16),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.heading,
    required this.onClose,
    required this.onHelp,
  });

  final String heading;
  final VoidCallback? onClose;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        if (onClose != null) ...[
          IconButton(
            onPressed: onClose,
            icon: const Icon(Symbols.close),
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(heading, style: AppTextStyles.vehicleName),
          ),
        ),
        TextButton(
          onPressed: onHelp,
          style: TextButton.styleFrom(foregroundColor: tokens.accent),
          child: Text(
            'Help',
            style: AppTextStyles.wizardBody.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// One segment per stage, lit up to the current one. The step label next to it
/// says the same for screen readers.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.stage});

  final WizardStage stage;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ExcludeSemantics(
      child: Row(
        spacing: 6,
        children: [
          for (final segment in WizardStage.values)
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: segment.index <= stage.index
                      ? tokens.accent
                      : tokens.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The large icon in the middle of a step, with pulsing [rings] while the app
/// is waiting for the device.
class WizardMedallion extends StatelessWidget {
  const WizardMedallion({
    super.key,
    required this.icon,
    this.rings = false,
    this.danger = false,
  });

  final IconData icon;
  final bool rings;

  /// Uses the failure colours, whatever the skin.
  final bool danger;

  static const double _size = 176;
  static const double _discSize = 112;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (rings) const Positioned.fill(child: _Rings()),
          Container(
            width: _discSize,
            height: _discSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: danger ? colors.errorContainer : tokens.accentContainer,
            ),
            child: Icon(
              icon,
              size: 52,
              color: danger ? tokens.danger : tokens.onAccentContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _Rings extends StatefulWidget {
  const _Rings();

  @override
  State<_Rings> createState() => _RingsState();
}

class _RingsState extends State<_Rings> with SingleTickerProviderStateMixin {
  static const _count = 3;

  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion: one ring that stays still.
    if (MediaQuery.disableAnimationsOf(context)) {
      return const _Ring(scale: 1, opacity: 0.25);
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < _count; i++)
              _ringAt((_controller.value + i / _count) % 1),
          ],
        ),
      ),
    );
  }

  Widget _ringAt(double phase) {
    final t = Curves.easeOut.transform(phase);
    return _Ring(scale: 0.62 + 0.46 * t, opacity: 0.55 * (1 - t));
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.scale, required this.opacity});

  final double scale;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: context.tokens.accent, width: 2),
          ),
        ),
      ),
    );
  }
}

/// A frosted card in the middle of a step.
class WizardCard extends StatelessWidget {
  const WizardCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // A Material, so a list tile inside it can draw its ripple.
    return Material(
      color: tokens.glassFill,
      shape: tokens.radiusMedium.shape(
        side: BorderSide(color: tokens.tileBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: child,
      ),
    );
  }
}

/// A short note in the accent colours.
class WizardNote extends StatelessWidget {
  const WizardNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: ShapeDecoration(
        color: tokens.accentContainer,
        shape: tokens.radiusMedium.shape(),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Icon(Symbols.info, size: 20, color: tokens.onAccentContainer),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.wizardNote.copyWith(
                color: tokens.onAccentContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The filled, full-width button of a step.
class WizardPrimaryButton extends StatelessWidget {
  const WizardPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: Text(label, style: AppTextStyles.wizardButton),
    );
  }
}

/// The outlined, full-width button of a step.
class WizardSecondaryButton extends StatelessWidget {
  const WizardSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: Text(label, style: AppTextStyles.wizardButton),
    );
  }
}
