import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/tiles/command_control.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';
import 'package:open_car_app/widgets/tiles/tile_icon.dart';

/// The span of [EditActionsTile]: wide enough for its three buttons, and one
/// tile so that they always share a row.
const kEditActionsSpan = TileSpan(2, 1);

const _dashLength = 5.0;
const _dashGap = 4.0;

/// A tile in edit mode: dimmed under a dashed outline, with a remove button
/// and, if it has several sizes, a size badge. The tile underneath can't be
/// operated, so its command can't run.
class EditingTile extends StatelessWidget {
  const EditingTile({
    super.key,
    required this.tile,
    required this.span,
    required this.child,
    this.onRemove,
    this.onNextSize,
    this.onMoveEarlier,
    this.onMoveLater,
  });

  final TileDefinition tile;
  final TileSpan span;
  final Widget child;

  /// Null when the tile can't be removed.
  final VoidCallback? onRemove;

  /// Null when the tile has only one size.
  final VoidCallback? onNextSize;

  /// Null when the tile is already first.
  final VoidCallback? onMoveEarlier;

  /// Null when the tile is already last.
  final VoidCallback? onMoveLater;

  static const moveEarlierAction = CustomSemanticsAction(label: 'Move earlier');
  static const moveLaterAction = CustomSemanticsAction(label: 'Move later');

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      label: tile.accessibleLabel,
      customSemanticsActions: {
        moveEarlierAction: ?onMoveEarlier,
        moveLaterAction: ?onMoveLater,
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(child: IgnorePointer(child: child)),
          IgnorePointer(
            child: CustomPaint(
              painter: _DashedOutlinePainter(
                shape: tokens.radiusMedium.shape(),
                color: tokens.textSecondary,
                fill: tokens.editScrim,
              ),
            ),
          ),
          // The badge sits opposite the remove button so that the two touch
          // targets stay apart on a 1×1 tile.
          if (onNextSize case final onNextSize?)
            Align(
              alignment: Alignment.bottomLeft,
              child: _SizeBadge(span: span, onPressed: onNextSize),
            ),
          if (onRemove case final onRemove?)
            Align(
              alignment: Alignment.topRight,
              // No tooltip: its hold would take the touch from dragging, and
              // this button covers much of a small tile.
              child: Semantics(
                button: true,
                label: 'Remove ${tile.accessibleLabel}',
                excludeSemantics: true,
                onTap: onRemove,
                child: IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 18),
                  color: tokens.text,
                  constraints: const BoxConstraints.tightFor(
                    width: kMinTouchTarget,
                    height: kMinTouchTarget,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SizeBadge extends StatelessWidget {
  const _SizeBadge({required this.span, required this.onPressed});

  final TileSpan span;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      button: true,
      label: 'Size $span, change size',
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: kMinTouchTarget - 12,
              minHeight: kMinTouchTarget - 12,
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: tokens.surface,
                  shape: tokens.radiusSmall.shape(
                    side: BorderSide(color: tokens.outline),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    '$span',
                    style: AppTextStyles.caption.copyWith(color: tokens.text),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The dotted pencil tile at the end of an explicitly editable grid.
class EditLayoutTile extends StatelessWidget {
  const EditLayoutTile({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return CustomPaint(
      painter: _DashedOutlinePainter(
        shape: tokens.radiusMedium.shape(),
        color: tokens.textSecondary,
      ),
      child: SizedBox.expand(
        child: IconButton(
          onPressed: onPressed,
          tooltip: 'Edit layout',
          icon: const Icon(Icons.edit_outlined),
          color: tokens.textSecondary,
        ),
      ),
    );
  }
}

/// The end of the grid in edit mode: add a tile, done and reset.
class EditActionsTile extends StatelessWidget {
  const EditActionsTile({
    super.key,
    required this.onAdd,
    required this.onDone,
    required this.onReset,
  });

  /// Null when the catalog has nothing left to add.
  final VoidCallback? onAdd;
  final VoidCallback onDone;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget button(String tooltip, IconData icon, VoidCallback? onPressed) =>
        Expanded(
          child: IconButton(
            onPressed: onPressed,
            tooltip: tooltip,
            icon: Icon(icon),
            color: tokens.text,
            padding: EdgeInsets.zero,
          ),
        );
    return CustomPaint(
      painter: _DashedOutlinePainter(
        shape: tokens.radiusMedium.shape(),
        color: tokens.textSecondary,
      ),
      child: Row(
        children: [
          button('Add a tile', Icons.add, onAdd),
          button('Done', Icons.check, onDone),
          button('Reset layout', Icons.undo, onReset),
        ],
      ),
    );
  }
}

/// A tile for the "Add a tile" list.
typedef AddableTile = ({TileDefinition tile, bool supported});

/// Lists [tiles] and returns the one picked, if any. A tile the car doesn't
/// support is shown greyed out and can't be picked.
Future<TileDefinition?> showAddTileSheet(
  BuildContext context,
  List<AddableTile> tiles,
) => showModalBottomSheet<TileDefinition>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      children: [
        for (final (:tile, :supported) in tiles)
          ListTile(
            enabled: supported,
            leading: tile.icon == null ? null : TileIconView(tile.icon!),
            title: Text(tile.accessibleLabel),
            subtitle: supported ? null : const Text('Not on this car'),
            onTap: () => Navigator.pop(context, tile),
          ),
      ],
    ),
  ),
);

class _DashedOutlinePainter extends CustomPainter {
  const _DashedOutlinePainter({
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
  bool shouldRepaint(_DashedOutlinePainter old) =>
      old.shape != shape || old.color != color || old.fill != fill;
}
