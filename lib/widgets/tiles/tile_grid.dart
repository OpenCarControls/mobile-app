import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// The height of a grid row in dp, before scaling with the system font size.
const double kTileRowHeight = 64;

/// The gap between tiles in dp.
const double kTileGap = 8;

/// The number of columns on phones.
const int kTileColumnsPhone = 4;

/// The number of columns on the wide Bluetooth layout.
const int kTileColumnsWide = 8;

const _resizeDuration = Duration(milliseconds: 250);

/// The size of a tile in whole grid columns and rows.
@immutable
class TileSpan {
  const TileSpan(this.columns, this.rows)
    : assert(columns > 0),
      assert(rows > 0);

  final int columns;
  final int rows;

  @override
  bool operator ==(Object other) =>
      other is TileSpan && other.columns == columns && other.rows == rows;

  @override
  int get hashCode => Object.hash(columns, rows);

  @override
  String toString() => '$columns×$rows';
}

/// Where a tile sits in the grid, in whole columns and rows.
typedef TileCell = ({int column, int row, int columns, int rows});

/// Places tiles of the given [spans] in order on a grid of [columns], each in
/// the first free spot from the top left. Later tiles fill the gaps earlier
/// ones left (a dense flow), so mixed sizes leave no avoidable holes.
///
/// A tile wider than the grid is narrowed to fit.
List<TileCell> packTiles(List<TileSpan> spans, int columns) {
  assert(columns > 0);
  final occupied = <List<bool>>[];

  bool fits(int column, int row, int width, int height) {
    for (var r = row; r < row + height && r < occupied.length; r++) {
      for (var c = column; c < column + width; c++) {
        if (occupied[r][c]) return false;
      }
    }
    return true;
  }

  return [
    for (final span in spans)
      () {
        final width = math.min(span.columns, columns);
        for (var row = 0; ; row++) {
          for (var column = 0; column <= columns - width; column++) {
            if (!fits(column, row, width, span.rows)) continue;
            while (occupied.length < row + span.rows) {
              occupied.add(List.filled(columns, false));
            }
            for (var r = row; r < row + span.rows; r++) {
              occupied[r].fillRange(column, column + width, true);
            }
            return (column: column, row: row, columns: width, rows: span.rows);
          }
        }
      }(),
  ];
}

/// What a [TileGrid] tells the owner of a tile the user holds and drags.
@immutable
class TileDragHandlers {
  const TileDragHandlers({required this.onStart, required this.onMoveTo});

  /// The tile was held long enough to start dragging.
  final VoidCallback onStart;

  /// The tile was dragged to another place: [index] counts only the items
  /// that can be dragged.
  final ValueChanged<int> onMoveTo;
}

/// One tile of a [TileGrid].
@immutable
class TileGridItem {
  const TileGridItem({
    required this.id,
    required this.span,
    required this.child,
    this.drag,
  });

  /// Stable and unique in the grid. It keeps a tile's state when it moves.
  final String id;
  final TileSpan span;
  final Widget child;

  /// How the tile is dragged, or null if it can't be. Items that can't be
  /// dragged must come after those that can.
  final TileDragHandlers? drag;
}

/// Lays out [items] on a grid of equal columns and rows.
///
/// The grid only places what it's given. The owner decides which tiles are in
/// [items] and their spans, so to resize a tile it changes that tile's span,
/// and to move one it reorders [items]. The tiles then slide to their new
/// places, and the grid's height follows.
class TileGrid extends StatefulWidget {
  const TileGrid({
    super.key,
    required this.items,
    this.columns = kTileColumnsPhone,
    this.rowHeight = kTileRowHeight,
    this.gap = kTileGap,
  });

  final List<TileGridItem> items;
  final int columns;

  /// The height of every row, before scaling with the system font size.
  final double rowHeight;
  final double gap;

  @override
  State<TileGrid> createState() => _TileGridState();
}

class _TileGridState extends State<TileGrid> {
  String? _draggingId;

  /// Where the dragged tile's top left corner is, in the grid.
  Offset _dragPosition = Offset.zero;

  /// Where the finger holds the dragged tile, from its top left corner.
  Offset _grab = Offset.zero;

  /// The size of a cell at the last layout.
  double _cellWidth = 0;
  double _cellHeight = 0;

  Offset _origin(TileCell cell) => Offset(
    cell.column * (_cellWidth + widget.gap),
    cell.row * (_cellHeight + widget.gap),
  );

  void _onDragStart(TileGridItem item, LongPressStartDetails details) {
    final index = widget.items.indexOf(item);
    final cell = _pack(widget.items)[index];
    HapticFeedback.mediumImpact();
    setState(() {
      _draggingId = item.id;
      _grab = details.localPosition;
      _dragPosition = _origin(cell);
    });
    item.drag!.onStart();
  }

  void _onDragUpdate(LongPressMoveUpdateDetails details) {
    final items = widget.items;
    final item = items.where((i) => i.id == _draggingId).firstOrNull;
    final drag = item?.drag;
    if (item == null || drag == null) return;
    final box = context.findRenderObject()! as RenderBox;
    setState(() {
      _dragPosition = box.globalToLocal(details.globalPosition) - _grab;
    });
    final current = items.where((i) => i.drag != null).toList().indexOf(item);
    final target = _closestIndex(item, current);
    if (target != current) drag.onMoveTo(target);
  }

  /// The place among the draggable items where [dragged] would land nearest
  /// to the finger. The other tiles keep their order whichever place it takes,
  /// so the answer depends only on where the finger is. Among places that land
  /// it in the same spot, it stays at [current].
  int _closestIndex(TileGridItem dragged, int current) {
    final others = [
      for (final item in widget.items)
        if (item.drag != null && item != dragged) item,
    ];
    final fixed = [
      for (final item in widget.items)
        if (item.drag == null) item,
    ];
    var best = 0;
    var bestDistance = double.infinity;
    for (var index = 0; index <= others.length; index++) {
      final cells = _pack([
        ...others.take(index),
        dragged,
        ...others.skip(index),
        ...fixed,
      ]);
      final distance = (_origin(cells[index]) - _dragPosition).distanceSquared;
      if (distance < bestDistance ||
          (distance == bestDistance && index == current)) {
        best = index;
        bestDistance = distance;
      }
    }
    return best;
  }

  void _onDragEnd() => setState(() => _draggingId = null);

  List<TileCell> _pack(List<TileGridItem> items) =>
      packTiles([for (final item in items) item.span], widget.columns);

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final columns = widget.columns;
    final gap = widget.gap;
    // Rows stay equal at any font size. Measured at body size: the system can
    // scale large sizes less than small ones, and tile text is small.
    const referenceSize = 14.0;
    final scaler = MediaQuery.textScalerOf(context);
    final height =
        widget.rowHeight * scaler.scale(referenceSize) / referenceSize;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _resizeDuration;
    final cells = _pack(items);
    final rows = cells.fold(0, (last, c) => math.max(last, c.row + c.rows));

    double extent(int cells, double cell) => cells * cell + (cells - 1) * gap;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        _cellWidth = width;
        _cellHeight = height;

        Widget tile(int index, TileGridItem item) {
          final dragging = item.id == _draggingId;
          final cell = cells[index];
          final origin = dragging ? _dragPosition : _origin(cell);
          return AnimatedPositioned(
            key: ValueKey(item.id),
            // The dragged tile follows the finger; the others slide away.
            duration: dragging ? Duration.zero : duration,
            curve: Curves.easeOutCubic,
            left: origin.dx,
            top: origin.dy,
            width: extent(cell.columns, width),
            height: extent(cell.rows, height),
            child: item.drag == null
                ? item.child
                : GestureDetector(
                    // The tile under it may not take touches, as in edit mode.
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: (details) => _onDragStart(item, details),
                    onLongPressMoveUpdate: _onDragUpdate,
                    onLongPressEnd: (_) => _onDragEnd(),
                    onLongPressCancel: _onDragEnd,
                    child: item.child,
                  ),
          );
        }

        return AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          height: rows == 0 ? 0 : extent(rows, height),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final (index, item) in items.indexed)
                if (item.id != _draggingId) tile(index, item),
              // Last, so that it passes over the others.
              for (final (index, item) in items.indexed)
                if (item.id == _draggingId) tile(index, item),
            ],
          ),
        );
      },
    );
  }
}
