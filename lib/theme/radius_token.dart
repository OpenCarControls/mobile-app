import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

/// A corner radius from a skin: a plain number in dp, or "full" (a stadium, or
/// a circle on a square box).
///
/// This is the one place that handles "full". Components build their shapes
/// from a token and never hard-code a radius.
@immutable
class RadiusToken {
  const RadiusToken(double this.radius);

  const RadiusToken._full() : radius = null;

  static const full = RadiusToken._full();

  /// Stands in for "full" where only a [BorderRadius] fits. It is clamped to
  /// half the box's shortest side when painted.
  static const double _fullRadius = 9999;

  /// The radius in dp, or null when the token is [full].
  final double? radius;

  bool get isFull => radius == null;

  /// The shape for a box with this radius, for buttons and [ShapeDecoration].
  OutlinedBorder shape({BorderSide side = BorderSide.none}) {
    final value = radius;
    if (value == null) return StadiumBorder(side: side);
    return RoundedRectangleBorder(
      side: side,
      borderRadius: BorderRadius.circular(value),
    );
  }

  /// The same corners as a [BorderRadius], for what doesn't take a shape, like
  /// [ClipRRect] or [OutlineInputBorder].
  BorderRadius get borderRadius => BorderRadius.circular(radius ?? _fullRadius);

  /// Numbers interpolate. There is no halfway to "full", so that switches
  /// at the midpoint.
  static RadiusToken lerp(RadiusToken a, RadiusToken b, double t) {
    final from = a.radius;
    final to = b.radius;
    if (from == null || to == null) return t < 0.5 ? a : b;
    return RadiusToken(lerpDouble(from, to, t)!);
  }

  @override
  bool operator ==(Object other) =>
      other is RadiusToken && other.radius == radius;

  @override
  int get hashCode => radius.hashCode;

  @override
  String toString() => isFull ? 'full' : '$radius';
}
