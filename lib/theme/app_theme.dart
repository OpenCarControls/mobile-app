import 'package:flutter/material.dart';

import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';

/// The typeface of the whole app. See `assets/fonts`.
const kAppFontFamily = 'Manrope';

/// Builds the app's theme for a skin and brightness: [AppTokens] as an
/// extension, plus the Material theme derived from them so stock widgets
/// (dialogs, snackbars, buttons) match.
ThemeData buildAppTheme(VehicleSkin skin, Brightness brightness) {
  final tokens = AppTokens.resolve(skin, brightness);
  final opposite = brightness == Brightness.light
      ? Brightness.dark
      : Brightness.light;
  final buttonShape = WidgetStatePropertyAll(tokens.radiusMedium.shape());
  // A disabled switch keeps Material's colours.
  WidgetStateProperty<Color?> switchColor({Color? on, Color? off}) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return null;
        return states.contains(WidgetState.selected) ? on : off;
      });

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: kAppFontFamily,
    colorScheme: _colorScheme(
      tokens,
      brightness,
      inversePrimary: skin.accentsFor(opposite).accent,
    ),
    scaffoldBackgroundColor: tokens.bg,
    extensions: [tokens],
    appBarTheme: AppBarTheme(
      backgroundColor: tokens.bg,
      foregroundColor: tokens.text,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: tokens.surface,
      surfaceTintColor: Colors.transparent,
      shape: tokens.radiusMedium.shape(),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surface,
      surfaceTintColor: Colors.transparent,
      shape: tokens.radiusLarge.shape(),
      barrierColor: tokens.modalScrim,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: tokens.modalScrim,
      shape: RoundedRectangleBorder(
        borderRadius: tokens.radiusLarge.borderRadius.copyWith(
          bottomLeft: Radius.zero,
          bottomRight: Radius.zero,
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.surface,
      surfaceTintColor: Colors.transparent,
      shape: tokens.radiusMedium.shape(),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: tokens.radiusMedium.shape(),
    ),
    chipTheme: ChipThemeData(shape: tokens.radiusPill.shape()),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(shape: buttonShape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(shape: buttonShape),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(shape: buttonShape),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(shape: buttonShape),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(tokens.radiusSmall.shape()),
      ),
    ),
    // On matches the selected segment of a segmented button. Material draws
    // an off switch in the outline colour, which is too faint here: it would
    // look disabled.
    switchTheme: SwitchThemeData(
      thumbColor: switchColor(
        on: tokens.onAccentContainer,
        off: tokens.textSecondary,
      ),
      trackColor: switchColor(on: tokens.accentContainer),
      trackOutlineColor: switchColor(off: tokens.textSecondary),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      border: OutlineInputBorder(borderRadius: tokens.radiusSmall.borderRadius),
    ),
  );
}

ColorScheme _colorScheme(
  AppTokens tokens,
  Brightness brightness, {
  required Color inversePrimary,
}) {
  // Material's tonal surfaces: the solid surface with a little of the text
  // colour mixed in, so each step moves away from the surface in both
  // brightnesses.
  Color tone(double amount) =>
      Color.alphaBlend(tokens.text.withValues(alpha: amount), tokens.surface);

  return ColorScheme(
    brightness: brightness,
    primary: tokens.accent,
    onPrimary: tokens.surface,
    primaryContainer: tokens.accentContainer,
    onPrimaryContainer: tokens.onAccentContainer,
    // A skin has one accent, so the secondary and tertiary roles repeat it.
    secondary: tokens.accent,
    onSecondary: tokens.surface,
    secondaryContainer: tokens.accentContainer,
    onSecondaryContainer: tokens.onAccentContainer,
    tertiary: tokens.accent,
    onTertiary: tokens.surface,
    tertiaryContainer: tokens.accentContainer,
    onTertiaryContainer: tokens.onAccentContainer,
    error: tokens.danger,
    onError: tokens.onDanger,
    errorContainer: Color.alphaBlend(
      tokens.danger.withValues(alpha: 0.12),
      tokens.surface,
    ),
    onErrorContainer: tokens.danger,
    surface: tokens.surface,
    onSurface: tokens.text,
    onSurfaceVariant: tokens.textSecondary,
    surfaceContainerLowest: tokens.surface,
    surfaceContainerLow: tone(0.02),
    surfaceContainer: tone(0.04),
    surfaceContainerHigh: tone(0.06),
    surfaceContainerHighest: tone(0.08),
    outline: tokens.outline,
    outlineVariant: tokens.outline,
    inverseSurface: tokens.text,
    onInverseSurface: tokens.surface,
    inversePrimary: inversePrimary,
    surfaceTint: Colors.transparent,
  );
}
