import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/widgets/tiles/command_tile.dart';
import 'package:open_car_app/widgets/tiles/tile_context.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';
import 'package:open_car_app/widgets/tiles/tile_icon.dart';

/// A catalog command tile: icon and title (or the icon alone), filled while
/// on, with the state as a caption at 2×1.
class CatalogCommandTile extends ConsumerWidget {
  const CatalogCommandTile({
    super.key,
    required this.tile,
    required this.span,
    required this.data,
  });

  final CommandTileDefinition tile;
  final TileSpan span;
  final TileContext data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = data.snapshot;
    final state = tile.state(snapshot);
    final wide = span.columns >= 2;
    final icon = TileIconView(tile.icon, on: state.on, size: 22);
    final title = Text(
      tile.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.buttonTitle,
    );
    final content = tile.content;
    return CommandTile(
      id: tile.id,
      command: tile.command.key,
      unavailableReason: tile.command.unavailableReason?.call(snapshot),
      send: () => ref.read(tileCommandSenderProvider)(
        tile.command.key,
        tile.command.build(snapshot),
      ),
      activityName: tile.command.activityName(snapshot),
      on: state.on,
      semanticLabel: '${tile.accessibleLabel}, ${state.caption.toLowerCase()}',
      child: content != null
          ? content(context, (
              snapshot: snapshot,
              units: data.units,
              span: span,
              state: state,
            ))
          : data.iconOnly && !wide
          ? Center(child: TileIconView(tile.icon, on: state.on))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                icon,
                Row(
                  children: [
                    if (!data.iconOnly) Flexible(child: title),
                    if (wide) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}
