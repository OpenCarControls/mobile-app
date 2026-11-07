import 'dart:math' as math;

import 'package:flutter/material.dart';

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

/// One tile of a [TileGrid].
@immutable
class TileGridItem {
  const TileGridItem({
    required this.id,
    required this.span,
    required this.child,
  });

  /// Stable and unique in the grid. It keeps a tile's state when it moves.
  final String id;
  final TileSpan span;
  final Widget child;
}

/// Lays out [items] on a grid of equal columns and rows.
///
/// The grid only places what it's given. The owner decides which tiles are in
/// [items] and their spans, so to resize a tile it changes that tile's span.
/// The tiles after it then slide to their new places, and the grid's height
/// follows.
class TileGrid extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // Rows stay equal at any font size. Measured at body size: the system can
    // scale large sizes less than small ones, and tile text is small.
    const referenceSize = 14.0;
    final scaler = MediaQuery.textScalerOf(context);
    final height = rowHeight * scaler.scale(referenceSize) / referenceSize;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _resizeDuration;
    final cells = packTiles([for (final item in items) item.span], columns);
    final rows = cells.fold(0, (last, c) => math.max(last, c.row + c.rows));

    double extent(int cells, double cell) => cells * cell + (cells - 1) * gap;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          height: rows == 0 ? 0 : extent(rows, height),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final (index, item) in items.indexed)
                AnimatedPositioned(
                  key: ValueKey(item.id),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  left: cells[index].column * (width + gap),
                  top: cells[index].row * (height + gap),
                  width: extent(cells[index].columns, width),
                  height: extent(cells[index].rows, height),
                  child: item.child,
                ),
            ],
          ),
        );
      },
    );
  }
}
