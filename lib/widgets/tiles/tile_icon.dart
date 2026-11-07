import 'package:flutter/material.dart';

/// Draws a custom tile icon on a 24 × 24 grid, scaled to [size] by the caller.
/// [stroke] is set up in the icon colour with the standard line weight; [on]
/// picks the "on" drawing (an open trunk, a lowered window).
typedef TileIconDrawing =
    void Function(Canvas canvas, Paint stroke, Paint fill, bool on);

/// The icon of a tile or a climate extra, with an "off" and an "on" look.
///
/// Material Symbols covers climate well, but has nothing for much of the car
/// body (trunk, frunk, car windows), so a platform can draw its own. Icons stay
/// per tile, not in the skin.
@immutable
sealed class TileIcon {
  const TileIcon();

  /// A Material Symbol. Off is the outline; on is [onSymbol] if given, or the
  /// same glyph filled.
  const factory TileIcon.symbol(IconData symbol, {IconData? onSymbol}) =
      SymbolTileIcon;

  /// A custom vector drawing.
  const factory TileIcon.drawn(TileIconDrawing draw) = DrawnTileIcon;
}

final class SymbolTileIcon extends TileIcon {
  const SymbolTileIcon(this.symbol, {this.onSymbol});

  final IconData symbol;
  final IconData? onSymbol;
}

final class DrawnTileIcon extends TileIcon {
  const DrawnTileIcon(this.draw);

  final TileIconDrawing draw;
}

/// Shows a [TileIcon] in the surrounding [IconTheme]'s colour and size.
class TileIconView extends StatelessWidget {
  const TileIconView(this.icon, {super.key, this.on = false, this.size});

  final TileIcon icon;
  final bool on;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    final color = theme.color ?? DefaultTextStyle.of(context).style.color!;
    return switch (icon) {
      SymbolTileIcon(:final symbol, :final onSymbol) => Icon(
        on ? onSymbol ?? symbol : symbol,
        fill: on && onSymbol == null ? 1 : 0,
        size: size,
        color: color,
      ),
      DrawnTileIcon(:final draw) => ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size),
          painter: _DrawnIconPainter(draw, on, color),
        ),
      ),
    };
  }
}

class _DrawnIconPainter extends CustomPainter {
  _DrawnIconPainter(this.draw, this.on, this.color);

  final TileIconDrawing draw;
  final bool on;
  final Color color;

  /// Material Symbols' outlined weight 400 on the 24 dp grid.
  static const _strokeWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    draw(canvas, stroke, fill, on);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DrawnIconPainter old) =>
      old.draw != draw || old.on != on || old.color != color;
}
