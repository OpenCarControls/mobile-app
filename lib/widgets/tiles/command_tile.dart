import 'package:flutter/material.dart';

import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/tiles/command_control.dart';
import 'package:open_car_app/widgets/tiles/tile_surface.dart';

/// A tile that sends a command when tapped, and can show a state: [on] gives
/// it the accent fill, and [child] is whatever the tile shows.
class CommandTile extends StatelessWidget {
  const CommandTile({
    super.key,
    required this.id,
    required this.command,
    required this.send,
    required this.semanticLabel,
    required this.child,
    this.on = false,
  });

  /// The tile's id. See [CommandControl.id].
  final String id;
  final CommandKey command;
  final Future<Object?> Function() send;
  final String semanticLabel;
  final Widget child;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return CommandControl(
      id: id,
      command: command,
      send: send,
      semanticLabel: semanticLabel,
      shape: context.tokens.radiusMedium.shape(),
      child: TileSurface(on: on, child: child),
    );
  }
}
