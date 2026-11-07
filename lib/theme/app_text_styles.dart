import 'package:flutter/painting.dart';

/// The type scale of the shared UI. Shared by all skins, like the typeface.
///
/// Each style sets only size and weight, so the family and colour come from
/// the surrounding theme.
abstract final class AppTextStyles {
  static const vehicleName = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
  );
  static const level = TextStyle(fontSize: 26, fontWeight: FontWeight.w800);
  static const range = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
  static const buttonTitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w400);
  static const statValue = TextStyle(fontSize: 18, fontWeight: FontWeight.w800);
  static const climateTarget = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
  );
}
