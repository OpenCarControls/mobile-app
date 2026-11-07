import 'dart:ui';

import 'package:open_car_app/widgets/tiles/tile_icon.dart';

/// Drawn icons for car body parts that Material Symbols lacks. They show a
/// generic hatchback from the side, front to the left, so any platform can use
/// them; a platform with a distinctive shape can draw its own.
abstract final class CarBodyIcons {
  /// The hood, raised when on.
  static const frunk = TileIcon.drawn(_drawFrunk);

  /// The tailgate, raised when on.
  static const trunk = TileIcon.drawn(_drawTrunk);

  /// A side window, lowered when on.
  static const window = TileIcon.drawn(_drawWindow);
}

void _drawWheels(Canvas canvas, Paint stroke) {
  canvas.drawCircle(const Offset(6.5, 17), 2, stroke);
  canvas.drawCircle(const Offset(17.5, 17), 2, stroke);
}

/// The sill between the wheels and the bumpers' lower edges.
void _drawSills(Canvas canvas, Paint stroke) {
  canvas.drawLine(const Offset(8.5, 17), const Offset(15.5, 17), stroke);
  canvas.drawLine(const Offset(2, 17), const Offset(4.5, 17), stroke);
  canvas.drawLine(const Offset(19.5, 17), const Offset(22, 17), stroke);
}

void _drawFrunk(Canvas canvas, Paint stroke, Paint fill, bool on) {
  _drawWheels(canvas, stroke);
  _drawSills(canvas, stroke);
  // The body from the front bumper over the roof to the rear bumper, without
  // the hood.
  canvas.drawPath(
    Path()
      ..moveTo(2, 17)
      ..lineTo(2, 12.5)
      ..moveTo(8, 11)
      ..lineTo(10.5, 7.5)
      ..lineTo(17, 7.5)
      ..lineTo(22, 11.5)
      ..lineTo(22, 17),
    stroke,
  );
  // The hood hinges at the windshield.
  canvas.drawLine(
    const Offset(8, 11),
    on ? const Offset(4, 5.5) : const Offset(2, 12.5),
    stroke,
  );
}

void _drawTrunk(Canvas canvas, Paint stroke, Paint fill, bool on) {
  _drawWheels(canvas, stroke);
  _drawSills(canvas, stroke);
  canvas.drawPath(
    Path()
      ..moveTo(22, 17)
      ..lineTo(22, 12.5)
      ..moveTo(17, 7.5)
      ..lineTo(7.5, 7.5)
      ..lineTo(5, 11)
      ..lineTo(2, 12)
      ..lineTo(2, 17),
    stroke,
  );
  // The tailgate hinges at the back of the roof.
  final tailgate = on
      ? (Path()
          ..moveTo(17, 7.5)
          ..lineTo(22.5, 3.5))
      : (Path()
          ..moveTo(17, 7.5)
          ..lineTo(22, 11.5)
          ..lineTo(22, 12.5));
  canvas.drawPath(tailgate, stroke);
}

void _drawWindow(Canvas canvas, Paint stroke, Paint fill, bool on) {
  final frame = Path()
    ..moveTo(4, 19)
    ..lineTo(4, 11)
    ..lineTo(10, 5)
    ..lineTo(20, 5)
    ..lineTo(20, 19)
    ..close();
  canvas.drawPath(frame, stroke);
  // The glass: up to the top when closed, its edge low in the frame when open.
  final glass = Path()
    ..moveTo(6.5, 16.5)
    ..lineTo(17.5, 16.5);
  if (on) {
    canvas.drawPath(
      glass
        ..lineTo(17.5, 14)
        ..lineTo(6.5, 14)
        ..close(),
      fill,
    );
  } else {
    canvas.drawPath(
      glass
        ..lineTo(17.5, 7.5)
        ..lineTo(11, 7.5)
        ..lineTo(6.5, 12)
        ..close(),
      Paint()
        ..color = fill.color.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );
  }
}
