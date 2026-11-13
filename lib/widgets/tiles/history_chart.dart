import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/theme/app_tokens.dart';

/// Draws recorded samples as lines in the accent colour, for sparklines and
/// chart tiles. Draws nothing until a line has two points.
///
/// Several [lines] share one vertical scale, so a minimum and a maximum can be
/// drawn together. The scale includes zero when [fromZero].
class HistoryChart extends StatelessWidget {
  const HistoryChart({super.key, required this.lines, this.fromZero = false});

  final List<List<HistorySample>> lines;
  final bool fromZero;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.infinite,
        painter: _HistoryPainter(lines, fromZero, tokens.accent),
      ),
    );
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter(this.lines, this.fromZero, this.color);

  final List<List<HistorySample>> lines;
  final bool fromZero;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final drawn = [
      for (final line in lines)
        if (line.length >= 2) line,
    ];
    if (drawn.isEmpty) return;
    final samples = drawn.expand((line) => line);
    var low = samples.map((s) => s.value).reduce(math.min);
    var high = samples.map((s) => s.value).reduce(math.max);
    if (fromZero) {
      low = math.min(low, 0);
      high = math.max(high, 0);
    }
    if (high - low < 1e-9) {
      // A flat line sits in the middle.
      low -= 1;
      high += 1;
    }
    final start = samples
        .map((s) => s.time)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final end = samples
        .map((s) => s.time)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final span = math.max(end.difference(start).inMilliseconds, 1);
    const stroke = 2.0;
    final height = size.height - stroke;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final line in drawn) {
      final path = Path();
      for (final (index, sample) in line.indexed) {
        final x =
            size.width * sample.time.difference(start).inMilliseconds / span;
        final y =
            stroke / 2 + height * (1 - (sample.value - low) / (high - low));
        index == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_HistoryPainter old) =>
      old.lines != lines || old.fromZero != fromZero || old.color != color;
}
