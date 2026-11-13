import 'package:material_ui/material_ui.dart';

const _dashLength = 5.0;
const _dashGap = 4.0;

/// Paints [shape] with a dashed outline, filled with [fill] if given: the
/// outline of something to add or of a tile being edited.
class DashedOutlinePainter extends CustomPainter {
  const DashedOutlinePainter({
    required this.shape,
    required this.color,
    this.fill,
  });

  final ShapeBorder shape;
  final Color color;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final path = shape.getOuterPath(Offset.zero & size);
    if (fill case final fill?) {
      canvas.drawPath(path, Paint()..color = fill);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dashLength + _dashGap) {
        canvas.drawPath(metric.extractPath(at, at + _dashLength), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedOutlinePainter old) =>
      old.shape != shape || old.color != color || old.fill != fill;
}
