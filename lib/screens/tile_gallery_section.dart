import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/tiles/command_control.dart';
import 'package:open_car_app/widgets/tiles/command_tile.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';
import 'package:open_car_app/widgets/tiles/tile_surface.dart';

/// How long a fake command takes to answer.
const fakeCommandDelay = Duration(milliseconds: 1200);

const _lock = (set: CommandSet.basic, id: 1);
const _lights = (set: CommandSet.basic, id: 2);
const _climate = (set: CommandSet.basic, id: 3);

/// Answers like a vehicle after [fakeCommandDelay], without sending anything.
Future<void> _fakeSend({bool fails = false}) async {
  await Future<void>.delayed(fakeCommandDelay);
  if (fails) throw StateError('The fake vehicle refused this command');
}

/// What the fake commands report, in place of the device's availability.
final _fakeAvailabilityProvider =
    NotifierProvider<_FakeAvailability, CommandUiState>(_FakeAvailability.new);

class _FakeAvailability extends Notifier<CommandUiState> {
  @override
  CommandUiState build() => CommandUiState.enabled;

  void set(CommandUiState value) => state = value;
}

/// A sandbox for the tile system: a small stand-in for the dashboard, with fake
/// tiles of every type. The commands are fake: the tiles get a send that only
/// waits, and an availability from the override here.
class TileGallerySection extends StatelessWidget {
  const TileGallerySection({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        commandUiStateProvider.overrideWith(
          (ref, key) => ref.watch(_fakeAvailabilityProvider),
        ),
      ],
      child: const _Sandbox(),
    );
  }
}

class _Sandbox extends ConsumerStatefulWidget {
  const _Sandbox();

  @override
  ConsumerState<_Sandbox> createState() => _SandboxState();
}

class _SandboxState extends ConsumerState<_Sandbox> {
  int _columns = kTileColumnsPhone;
  double _rowHeight = kTileRowHeight;

  // What the owner of a grid keeps: what decides each tile's span. The climate
  // tile's follows from its state, so the two can't disagree.
  bool _climateOn = false;
  TileSpan _resizableSpan = const TileSpan(1, 1);

  static const _resizableSpans = [
    TileSpan(1, 1),
    TileSpan(2, 1),
    TileSpan(2, 2),
    TileSpan(3, 2),
  ];

  void _nextResizableSpan() {
    final index = _resizableSpans.indexOf(_resizableSpan);
    setState(() {
      _resizableSpan = _resizableSpans[(index + 1) % _resizableSpans.length];
    });
  }

  @override
  Widget build(BuildContext context) {
    final availability = ref.watch(_fakeAvailabilityProvider);
    final hideCommands = availability == CommandUiState.hidden;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: kTileColumnsPhone, label: Text('4 columns')),
            ButtonSegment(value: kTileColumnsWide, label: Text('8 columns')),
          ],
          selected: {_columns},
          onSelectionChanged: (picked) =>
              setState(() => _columns = picked.single),
        ),
        const SizedBox(height: 8),
        SegmentedButton<CommandUiState>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: CommandUiState.enabled,
              label: Text('Available'),
            ),
            ButtonSegment(
              value: CommandUiState.disabled,
              label: Text('Greyed out'),
            ),
            ButtonSegment(value: CommandUiState.hidden, label: Text('Hidden')),
          ],
          selected: {availability},
          onSelectionChanged: (picked) =>
              ref.read(_fakeAvailabilityProvider.notifier).set(picked.single),
        ),
        Row(
          children: [
            Text('Row height ${_rowHeight.round()} dp'),
            Expanded(
              child: Slider(
                min: 64,
                max: 104,
                divisions: 10,
                value: _rowHeight,
                label: '${_rowHeight.round()}',
                onChanged: (value) => setState(() => _rowHeight = value),
              ),
            ),
          ],
        ),
        TileGrid(
          columns: _columns,
          rowHeight: _rowHeight,
          items: [
            if (!hideCommands) ...[
              TileGridItem(
                id: 'doors',
                span: const TileSpan(1, 1),
                child: _FakeToggleTile(
                  id: 'gallery.doors',
                  command: _lock,
                  icon: Symbols.lock,
                  title: 'Doors',
                ),
              ),
              TileGridItem(
                id: 'lights',
                span: const TileSpan(1, 1),
                child: _FakeToggleTile(
                  id: 'gallery.lights',
                  command: _lights,
                  icon: Symbols.lightbulb,
                  title: 'Fails',
                  fails: true,
                ),
              ),
              TileGridItem(
                id: 'icon-only',
                span: const TileSpan(1, 1),
                child: _FakeToggleTile(
                  id: 'gallery.icon-only',
                  command: _lock,
                  icon: Symbols.garage,
                  title: 'Garage',
                  iconOnly: true,
                ),
              ),
            ],
            TileGridItem(
              id: 'resizable',
              span: _resizableSpan,
              child: _FakeResizableTile(
                span: _resizableSpan,
                onTap: _nextResizableSpan,
              ),
            ),
            if (!hideCommands) ...[
              TileGridItem(
                id: 'climate',
                span: TileSpan(4, _climateOn ? 3 : 1),
                child: _FakeClimateTile(
                  on: _climateOn,
                  onChanged: (on) => setState(() => _climateOn = on),
                ),
              ),
              TileGridItem(
                id: 'caption',
                span: const TileSpan(2, 1),
                child: _FakeToggleTile(
                  id: 'gallery.caption',
                  command: _lock,
                  icon: Symbols.ev_station,
                  title: 'Port',
                  captions: ('Closed', 'Open'),
                ),
              ),
            ],
            const TileGridItem(
              id: 'speed',
              span: TileSpan(1, 1),
              child: _FakeStateTile(label: 'Speed', value: '0 km/h'),
            ),
            const TileGridItem(
              id: 'gear',
              span: TileSpan(1, 1),
              child: _FakeStateTile(label: 'Gear', value: 'P'),
            ),
            const TileGridItem(
              id: 'graph',
              span: TileSpan(2, 2),
              child: _FakeGraphTile(),
            ),
            const TileGridItem(
              id: 'wide-state',
              span: TileSpan(2, 1),
              child: _FakeStateTile(label: 'Odometer', value: '22,916 km'),
            ),
            const TileGridItem(
              id: 'tall-state',
              span: TileSpan(1, 2),
              child: _FakeStateTile(label: 'Tall', value: '1×2'),
            ),
            const TileGridItem(
              id: 'battery',
              span: TileSpan(4, 1),
              child: _FakeStateTile(label: 'Battery', value: '64%'),
            ),
          ],
        ),
      ],
    );
  }
}

/// A tile that only shows a value.
class _FakeStateTile extends StatelessWidget {
  const _FakeStateTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: TileSurface(
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: context.tokens.textSecondary),
                ),
                Text(value, style: AppTextStyles.statValue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A command tile whose fake command toggles it.
class _FakeToggleTile extends StatefulWidget {
  const _FakeToggleTile({
    required this.id,
    required this.command,
    required this.icon,
    required this.title,
    this.iconOnly = false,
    this.fails = false,
    this.captions,
  });

  final String id;
  final CommandKey command;
  final IconData icon;
  final String title;
  final bool iconOnly;
  final bool fails;

  /// The caption when off and when on.
  final (String, String)? captions;

  @override
  State<_FakeToggleTile> createState() => _FakeToggleTileState();
}

class _FakeToggleTileState extends State<_FakeToggleTile> {
  bool _on = false;

  Future<void> _send() async {
    await _fakeSend(fails: widget.fails);
    if (mounted) setState(() => _on = !_on);
  }

  @override
  Widget build(BuildContext context) {
    final captions = widget.captions;
    final state = captions == null
        ? (_on ? 'on' : 'off')
        : (_on ? captions.$2 : captions.$1);
    return CommandTile(
      id: widget.id,
      command: widget.command,
      send: _send,
      on: _on,
      semanticLabel: '${widget.title}, $state',
      child: widget.iconOnly
          ? Center(child: Icon(widget.icon, fill: _on ? 1 : 0))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(widget.icon, fill: _on ? 1 : 0, size: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.buttonTitle,
                      ),
                    ),
                    if (captions != null) Text(state),
                  ],
                ),
              ],
            ),
    );
  }
}

/// A tile that asks its owner for another size when tapped, to show the others
/// moving out of the way.
class _FakeResizableTile extends StatelessWidget {
  const _FakeResizableTile({required this.span, required this.onTap});

  final TileSpan span;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Resize, $span',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: TileSurface(
          child: Center(child: Text('$span', style: AppTextStyles.statValue)),
        ),
      ),
    );
  }
}

/// An advanced tile with its own UI: a bar with a power button, and while on, a
/// panel of more buttons. Its owner gives it more rows while it's on.
class _FakeClimateTile extends StatefulWidget {
  const _FakeClimateTile({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  State<_FakeClimateTile> createState() => _FakeClimateTileState();
}

class _FakeClimateTileState extends State<_FakeClimateTile> {
  int _target = 21;
  int _seat = 0;

  Future<void> _togglePower() async {
    await _fakeSend();
    if (mounted) widget.onChanged(!widget.on);
  }

  Future<void> _setTarget(int value) async {
    await _fakeSend();
    if (mounted) setState(() => _target = value);
  }

  Future<void> _cycleSeat() async {
    await _fakeSend();
    if (mounted) setState(() => _seat = (_seat + 1) % 4);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final on = widget.on;
    return TileSurface(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: SingleChildScrollView(
        // The panel is cut off while the tile grows, not laid out smaller.
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Symbols.thermostat),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Climate', style: AppTextStyles.buttonTitle),
                      Text(
                        'Inside 19.5° · Outside 12°',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
                _RoundButton(
                  id: 'gallery.climate.power',
                  icon: Symbols.power_settings_new,
                  label: 'Climate, ${on ? 'on' : 'off'}',
                  filled: on,
                  send: _togglePower,
                ),
              ],
            ),
            if (on) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _RoundButton(
                    id: 'gallery.climate.down',
                    icon: Symbols.remove,
                    label: 'Colder, target $_target degrees',
                    send: () => _setTarget(_target - 1),
                  ),
                  Expanded(
                    child: Text(
                      '$_target°C',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.climateTarget,
                    ),
                  ),
                  _RoundButton(
                    id: 'gallery.climate.up',
                    icon: Symbols.add,
                    label: 'Warmer, target $_target degrees',
                    send: () => _setTarget(_target + 1),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundButton(
                    id: 'gallery.climate.seat',
                    icon: Symbols.airline_seat_recline_normal,
                    label: 'Seat heating, level $_seat',
                    send: _cycleSeat,
                  ),
                  _RoundButton(
                    id: 'gallery.climate.fails',
                    icon: Symbols.mode_fan,
                    label: 'Fails',
                    send: () => _fakeSend(fails: true),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.id,
    required this.icon,
    required this.label,
    required this.send,
    this.filled = false,
  });

  final String id;
  final IconData icon;
  final String label;
  final Future<Object?> Function() send;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final shape = tokens.radiusRound.shape();
    return CommandControl(
      id: id,
      // The extras are all part of one command.
      command: _climate,
      send: send,
      semanticLabel: label,
      shape: shape,
      child: Container(
        width: kMinTouchTarget,
        height: kMinTouchTarget,
        decoration: ShapeDecoration(
          color: filled ? tokens.accent : tokens.surface,
          shape: shape.copyWith(side: BorderSide(color: tokens.outline)),
        ),
        child: Icon(icon, color: filled ? tokens.surface : tokens.text),
      ),
    );
  }
}

/// A custom tile that draws a chart from fixed data.
class _FakeGraphTile extends StatelessWidget {
  const _FakeGraphTile();

  static const _values = [
    2.0,
    3.0,
    2.0,
    5.0,
    4.0,
    6.0,
    4.5,
    7.0,
    5.5,
    6.5,
    6.0,
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      label: 'Power, 7.2 kilowatts',
      excludeSemantics: true,
      child: TileSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Power', style: TextStyle(color: tokens.textSecondary)),
            const Text('7.2 kW', style: AppTextStyles.statValue),
            const SizedBox(height: 4),
            Expanded(
              child: CustomPaint(
                size: Size.infinite,
                painter: _LinePainter(_values, tokens.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final top = values.reduce((a, b) => a > b ? a : b);
    final path = Path();
    for (final (index, value) in values.indexed) {
      final x = size.width * index / (values.length - 1);
      final y = size.height * (1 - value / top);
      index == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_LinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.values != values;
}
