import 'package:flutter/painting.dart';

import 'package:open_car_app/theme/radius_token.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';

/// The virtual car's skin: steel and boxy, so it looks different from E-GMP
/// and the skin path gets used on every platform build.
const virtualCarSkin = VehicleSkin(
  name: 'Boxy',
  light: SkinAccents(
    accent: Color(0xFF37474F),
    accentContainer: Color(0xFFCFD8DC),
    onAccentContainer: Color(0xFF1C262B),
  ),
  dark: SkinAccents(
    accent: Color(0xFFCFD8DC),
    accentContainer: Color(0xFF37474F),
    onAccentContainer: Color(0xFFECEFF1),
  ),
  shapes: SkinShapes.all(RadiusToken(2)),
);
