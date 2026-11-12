import 'package:material_ui/material_ui.dart';

import 'package:open_car_app/theme/radius_token.dart';

/// A skin's accent colours for one brightness.
@immutable
class SkinAccents {
  const SkinAccents({
    required this.accent,
    required this.accentContainer,
    required this.onAccentContainer,
  });

  final Color accent;
  final Color accentContainer;
  final Color onAccentContainer;
}

/// The five shape tokens of a skin. See `docs/ui-theming.md` for what each one
/// is used for.
@immutable
class SkinShapes {
  const SkinShapes({
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.radiusPill,
    required this.radiusRound,
  });

  /// Every token set to the same radius, for a boxy skin.
  const SkinShapes.all(RadiusToken radius)
    : radiusSmall = radius,
      radiusMedium = radius,
      radiusLarge = radius,
      radiusPill = radius,
      radiusRound = radius;

  final RadiusToken radiusSmall;
  final RadiusToken radiusMedium;
  final RadiusToken radiusLarge;
  final RadiusToken radiusPill;
  final RadiusToken radiusRound;
}

/// What a vehicle platform may customise: accent colours and shapes. Layout,
/// spacing, type, icons, motion and neutral colours are the same for everyone.
@immutable
class VehicleSkin {
  const VehicleSkin({
    required this.name,
    required this.light,
    required this.dark,
    required this.shapes,
  });

  /// A short name for the debug gallery.
  final String name;
  final SkinAccents light;
  final SkinAccents dark;
  final SkinShapes shapes;

  SkinAccents accentsFor(Brightness brightness) =>
      brightness == Brightness.light ? light : dark;
}

/// The default skin, also used before a vehicle is known (the pairing wizard).
const defaultSkin = VehicleSkin(
  name: 'Default',
  light: SkinAccents(
    accent: Color(0xFF1C68C5),
    accentContainer: Color(0xFFD5E4F8),
    onAccentContainer: Color(0xFF0B2A52),
  ),
  dark: SkinAccents(
    accent: Color(0xFF91B8EB),
    accentContainer: Color(0xFF163B66),
    onAccentContainer: Color(0xFFD5E6FF),
  ),
  shapes: SkinShapes(
    radiusSmall: RadiusToken(14),
    radiusMedium: RadiusToken(16),
    radiusLarge: RadiusToken(24),
    radiusPill: RadiusToken.full,
    radiusRound: RadiusToken.full,
  ),
);
