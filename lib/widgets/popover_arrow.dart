import 'package:flutter/material.dart';

/// The arrow at the top of a popover, pointing up at what opened it.
class PopoverArrowPainter extends CustomPainter {
  const PopoverArrowPainter({required this.fill, required this.border});

  final Color fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final edges = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);
    canvas.drawPath(edges, Paint()..color = fill);
    canvas.drawPath(
      edges,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(PopoverArrowPainter oldDelegate) =>
      fill != oldDelegate.fill || border != oldDelegate.border;
}
