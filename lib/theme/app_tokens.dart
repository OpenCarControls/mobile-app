import 'package:flutter/material.dart';

import 'package:open_car_app/theme/radius_token.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';

/// The design tokens from `docs/ui-theming.md`: the shared neutrals of one
/// brightness combined with a skin's accents and shapes.
///
/// Read them with `context.tokens`. Widgets take their colours and radii from
/// here, and never import a vehicle.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.bg,
    required this.surface,
    required this.text,
    required this.textSecondary,
    required this.accent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.outline,
    required this.tileBorder,
    required this.glassFill,
    required this.layerFill,
    required this.headerFill,
    required this.danger,
    required this.onDanger,
    required this.editScrim,
    required this.modalScrim,
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.radiusPill,
    required this.radiusRound,
  });

  factory AppTokens.resolve(VehicleSkin skin, Brightness brightness) {
    final accents = skin.accentsFor(brightness);
    final shapes = skin.shapes;
    final isLight = brightness == Brightness.light;
    final bg = isLight ? const Color(0xFFE9EBEE) : const Color(0xFF0E1013);
    final text = isLight ? const Color(0xFF15171A) : const Color(0xFFEAECEF);
    return AppTokens(
      bg: bg,
      surface: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF191B1E),
      text: text,
      textSecondary: isLight
          ? const Color(0xFF515356)
          : const Color(0xFFAAACAF),
      accent: accents.accent,
      accentContainer: accents.accentContainer,
      onAccentContainer: accents.onAccentContainer,
      outline: isLight ? const Color(0xFFCACCCF) : const Color(0xFF393B3E),
      tileBorder: text.withValues(alpha: isLight ? 0.12 : 0.14),
      glassFill: isLight
          ? const Color(0xFFFFFFFF).withValues(alpha: 0.82)
          : const Color(0xFF26282B).withValues(alpha: 0.80),
      layerFill: bg.withValues(alpha: 0.66),
      headerFill: bg.withValues(alpha: isLight ? 0.85 : 0.80),
      danger: isLight ? const Color(0xFFB3261E) : const Color(0xFFFFB4AB),
      onDanger: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF3B0A07),
      editScrim: bg.withValues(alpha: 0.60),
      modalScrim: const Color(
        0xFF000000,
      ).withValues(alpha: isLight ? 0.40 : 0.60),
      radiusSmall: shapes.radiusSmall,
      radiusMedium: shapes.radiusMedium,
      radiusLarge: shapes.radiusLarge,
      radiusPill: shapes.radiusPill,
      radiusRound: shapes.radiusRound,
    );
  }

  /// Page behind the hero.
  final Color bg;

  /// Solid surfaces: pill, round buttons, side column.
  final Color surface;

  /// Primary text and glyph outlines.
  final Color text;

  /// Range, captions, labels.
  final Color textSecondary;

  /// Level fill, active power button, charging text, dots.
  final Color accent;

  /// Fill of an "on" button.
  final Color accentContainer;

  /// Text and icons on [accentContainer].
  final Color onAccentContainer;

  /// Borders of solid controls, level track.
  final Color outline;

  /// The 1 px border of frosted surfaces.
  final Color tileBorder;

  /// Frosted tiles and cards.
  final Color glassFill;

  /// The frosted layer behind the tiles on the remote tier.
  final Color layerFill;

  /// The pinned header.
  final Color headerFill;

  /// Destructive actions and failures. The same for every skin.
  final Color danger;

  /// Text on a [danger] fill.
  final Color onDanger;

  /// Dims a tile in edit mode.
  final Color editScrim;

  /// Dims the screen behind a popover or dialog.
  final Color modalScrim;

  /// Small icon buttons in the climate panel, segmented controls.
  final RadiusToken radiusSmall;

  /// Tiles, the climate bar, cards, wizard buttons, dialog buttons.
  final RadiusToken radiusMedium;

  /// Popovers and dialogs, and the top corners of the remote tier's layer.
  final RadiusToken radiusLarge;

  /// Connection pill, chips, switches, the temperature stepper.
  final RadiusToken radiusPill;

  /// Circular icon buttons and vehicle avatars.
  final RadiusToken radiusRound;

  @override
  AppTokens copyWith({
    Color? bg,
    Color? surface,
    Color? text,
    Color? textSecondary,
    Color? accent,
    Color? accentContainer,
    Color? onAccentContainer,
    Color? outline,
    Color? tileBorder,
    Color? glassFill,
    Color? layerFill,
    Color? headerFill,
    Color? danger,
    Color? onDanger,
    Color? editScrim,
    Color? modalScrim,
    RadiusToken? radiusSmall,
    RadiusToken? radiusMedium,
    RadiusToken? radiusLarge,
    RadiusToken? radiusPill,
    RadiusToken? radiusRound,
  }) => AppTokens(
    bg: bg ?? this.bg,
    surface: surface ?? this.surface,
    text: text ?? this.text,
    textSecondary: textSecondary ?? this.textSecondary,
    accent: accent ?? this.accent,
    accentContainer: accentContainer ?? this.accentContainer,
    onAccentContainer: onAccentContainer ?? this.onAccentContainer,
    outline: outline ?? this.outline,
    tileBorder: tileBorder ?? this.tileBorder,
    glassFill: glassFill ?? this.glassFill,
    layerFill: layerFill ?? this.layerFill,
    headerFill: headerFill ?? this.headerFill,
    danger: danger ?? this.danger,
    onDanger: onDanger ?? this.onDanger,
    editScrim: editScrim ?? this.editScrim,
    modalScrim: modalScrim ?? this.modalScrim,
    radiusSmall: radiusSmall ?? this.radiusSmall,
    radiusMedium: radiusMedium ?? this.radiusMedium,
    radiusLarge: radiusLarge ?? this.radiusLarge,
    radiusPill: radiusPill ?? this.radiusPill,
    radiusRound: radiusRound ?? this.radiusRound,
  );

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other == null) return this;
    return AppTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t)!,
      onAccentContainer: Color.lerp(
        onAccentContainer,
        other.onAccentContainer,
        t,
      )!,
      outline: Color.lerp(outline, other.outline, t)!,
      tileBorder: Color.lerp(tileBorder, other.tileBorder, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      layerFill: Color.lerp(layerFill, other.layerFill, t)!,
      headerFill: Color.lerp(headerFill, other.headerFill, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      onDanger: Color.lerp(onDanger, other.onDanger, t)!,
      editScrim: Color.lerp(editScrim, other.editScrim, t)!,
      modalScrim: Color.lerp(modalScrim, other.modalScrim, t)!,
      radiusSmall: RadiusToken.lerp(radiusSmall, other.radiusSmall, t),
      radiusMedium: RadiusToken.lerp(radiusMedium, other.radiusMedium, t),
      radiusLarge: RadiusToken.lerp(radiusLarge, other.radiusLarge, t),
      radiusPill: RadiusToken.lerp(radiusPill, other.radiusPill, t),
      radiusRound: RadiusToken.lerp(radiusRound, other.radiusRound, t),
    );
  }
}

extension AppTokensContext on BuildContext {
  /// The resolved tokens. Needs a theme from `buildAppTheme` above this
  /// context.
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
}
