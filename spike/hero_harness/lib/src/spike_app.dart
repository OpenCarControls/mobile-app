import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

import 'metrics.dart';
import 'scene_state.dart';

/// The spike app for one renderer. Every candidate gets the same screens and
/// measurements, so their numbers compare.
class SpikeApp extends StatefulWidget {
  const SpikeApp({
    super.key,
    required this.name,
    required this.builder,
    this.tuning = const [],
  });

  final String name;
  final HeroRendererBuilder builder;
  final List<TuningKnob> tuning;

  @override
  State<SpikeApp> createState() => _SpikeAppState();
}

class _SpikeAppState extends State<SpikeApp> {
  final log = SpikeLog();
  late final metrics = SpikeMetrics(log);
  var _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    log.add('${widget.name} spike started');
  }

  @override
  void dispose() {
    metrics.dispose();
    log.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF00897B));
    return MaterialApp(
      title: '${widget.name} hero spike',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(colorScheme: scheme),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00897B),
          brightness: Brightness.dark,
        ),
      ),
      builder: (context, child) => Stack(
        children: [
          child!,
          Positioned(
            top: MediaQuery.paddingOf(context).top + 4,
            right: 4,
            child: _MetricsBadge(metrics: metrics),
          ),
        ],
      ),
      home: _Home(
        name: widget.name,
        builder: widget.builder,
        tuning: widget.tuning,
        log: log,
        metrics: metrics,
        onToggleTheme: () => setState(() {
          _themeMode = _themeMode == ThemeMode.light
              ? ThemeMode.dark
              : ThemeMode.light;
          log.add('theme: ${_themeMode.name}');
        }),
      ),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({
    required this.name,
    required this.builder,
    required this.tuning,
    required this.log,
    required this.metrics,
    required this.onToggleTheme,
  });

  final String name;
  final HeroRendererBuilder builder;
  final List<TuningKnob> tuning;
  final SpikeLog log;
  final SpikeMetrics metrics;
  final VoidCallback onToggleTheme;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            // Only the visible tab mounts renderers, so the checklist and grid
            // don't run viewers at the same time.
            _tab == 0
                ? _ChecklistScreen(
                    name: widget.name,
                    builder: widget.builder,
                    tuning: widget.tuning,
                    log: widget.log,
                    metrics: widget.metrics,
                    onToggleTheme: widget.onToggleTheme,
                  )
                : const SizedBox.shrink(),
            _tab == 1
                ? _GridScreen(
                    builder: widget.builder,
                    log: widget.log,
                    metrics: widget.metrics,
                  )
                : const SizedBox.shrink(),
            _LogScreen(log: widget.log),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        height: 60,
        onDestinationSelected: (i) {
          widget.log.add('tab: ${['checklist', 'grid', 'log'][i]}');
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist),
            label: 'Checklist',
          ),
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Grid'),
          NavigationDestination(icon: Icon(Icons.notes), label: 'Log'),
        ],
      ),
    );
  }
}

// ── Checklist screen (items 1–7, 9) ──────────────────────────────────────────

const _kPaints = {
  'Red': Color(0xFF5B0A02),
  'Blue': Color(0xFF0D2A6B),
  'White': Color(0xFFD8D8D8),
  'Green': Color(0xFF1F4D2B),
};

const _kWindowSteps = [0.0, 0.2, 0.6, 1.0];

class _ChecklistScreen extends StatefulWidget {
  const _ChecklistScreen({
    required this.name,
    required this.builder,
    required this.tuning,
    required this.log,
    required this.metrics,
    required this.onToggleTheme,
  });

  final String name;
  final HeroRendererBuilder builder;
  final List<TuningKnob> tuning;
  final SpikeLog log;
  final SpikeMetrics metrics;
  final VoidCallback onToggleTheme;

  @override
  State<_ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<_ChecklistScreen> {
  var _state = const HeroSceneState();
  var _model = SpikeModel.meshopt;
  var _mountId = 0;
  var _pauseWhenIdle = true;
  var _tall = true;
  var _narrow = false;
  var _under = true;
  var _over = true;
  Timer? _resizeTimer;
  var _scriptRunning = false;
  late final _tuning = {for (final k in widget.tuning) k.name: k.initial};

  @override
  void dispose() {
    _resizeTimer?.cancel();
    super.dispose();
  }

  void _set(HeroSceneState next, String what) {
    widget.log.add('state: $what');
    setState(() => _state = next);
  }

  void _toggleResizeLoop(bool on) {
    _resizeTimer?.cancel();
    _resizeTimer = null;
    if (on) {
      var step = 0;
      _resizeTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
        step++;
        setState(() {
          _tall = step % 2 == 0;
          _narrow = step % 4 >= 2;
        });
      });
    }
    widget.log.add('resize loop ${on ? 'on' : 'off'}');
    setState(() {});
  }

  /// Scripted run through camera, parts, lights and charging, ending with a
  /// metrics summary in the log.
  Future<void> _runScript() async {
    if (_scriptRunning) return;
    setState(() => _scriptRunning = true);
    widget.metrics.resetJank();
    widget.log.add('script: start');
    Future<void> step(String what, HeroSceneState next, int ms) async {
      if (!mounted) return;
      _set(next, 'script $what');
      await Future.delayed(Duration(milliseconds: ms));
    }

    var s = const HeroSceneState();
    await step('reset', s, 800);
    await step('rear view', s = s.copyWith(rearView: true), 1500);
    await step('port open', s = s.withPart('Anim_ChargePort', 1), 1500);
    await step('cable L2', s = s.copyWith(cable: Cable.l2), 1200);
    await step('power flow', s = s.copyWith(powerFlow: true), 2500);
    await step(
      'cable DC',
      s = s.copyWith(cable: Cable.dc, powerFlow: false),
      2000,
    );
    await step(
      'unplug, port closed, front',
      s = s
          .copyWith(cable: Cable.none, rearView: false)
          .withPart('Anim_ChargePort', 0),
      1800,
    );
    await step('lights', s = s.copyWith(lightsOn: true), 1000);
    await step('hazards', s = s.copyWith(hazards: true), 2500);
    var parts = <String, double>{
      'Anim_Door_FL': 1,
      'Anim_Door_FR': 1,
      'Anim_Door_RL': 1,
      'Anim_Door_RR': 1,
      'Anim_Hood': 1,
      'Anim_Trunk': 1,
    };
    await step('doors, hood, trunk open', s = s.copyWith(parts: parts), 2500);
    parts = {
      for (final w in ['FL', 'FR', 'RL', 'RR']) 'Anim_Window_$w': 0.6,
    };
    await step(
      'doors closed, windows partly',
      s = s.copyWith(parts: parts),
      2500,
    );
    await step('paint blue', s = s.copyWith(paint: _kPaints['Blue']), 1000);
    await step('reset', const HeroSceneState(), 2000);
    widget.log.add('script: done  ${widget.metrics.summary()}');
    if (mounted) setState(() => _scriptRunning = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final config = HeroRendererConfig(
      state: _state,
      model: _model,
      isDark: isDark,
      pauseWhenIdle: _pauseWhenIdle,
      tuning: Map.unmodifiable(_tuning),
      log: widget.log.add,
    );

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth * (_narrow ? 0.62 : 1);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeInOutCubic,
              width: width,
              height: _tall ? 340 : 200,
              child: _HeroBox(
                under: _under,
                over: _over,
                child: KeyedSubtree(
                  key: ValueKey('${_model.name}-$_mountId'),
                  child: widget.builder(context, config),
                ),
              ),
            );
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Text(
                '${widget.name} hero spike',
                style: theme.textTheme.titleMedium,
              ),
              _section('Model and start-up'),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<SpikeModel>(
                    segments: [
                      for (final m in SpikeModel.values)
                        ButtonSegment(value: m, label: Text(m.label)),
                    ],
                    selected: {_model},
                    onSelectionChanged: (s) {
                      widget.log.add('model: ${s.first.label} (remount)');
                      setState(() => _model = s.first);
                    },
                  ),
                  OutlinedButton(
                    onPressed: () {
                      widget.log.add('remount');
                      setState(() => _mountId++);
                    },
                    child: const Text('Remount'),
                  ),
                  FilterChip(
                    label: const Text('Pause when idle'),
                    selected: _pauseWhenIdle,
                    onSelected: (v) {
                      widget.log.add('pause when idle: $v');
                      setState(() => _pauseWhenIdle = v);
                    },
                  ),
                ],
              ),
              _section('Script'),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _scriptRunning ? null : _runScript,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(_scriptRunning ? 'Running…' : 'Run demo'),
                  ),
                  OutlinedButton(
                    onPressed: widget.metrics.resetJank,
                    child: const Text('Reset counters'),
                  ),
                  OutlinedButton(
                    onPressed: () => widget.log.add(widget.metrics.summary()),
                    child: const Text('Log metrics'),
                  ),
                ],
              ),
              _section('1–2 Camera'),
              _chip('Rear view', _state.rearView, (v) {
                _set(_state.copyWith(rearView: v), 'rear view $v');
              }),
              _section('3 Parts'),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final (label, anim) in [
                    ('Door FL', 'Anim_Door_FL'),
                    ('Door FR', 'Anim_Door_FR'),
                    ('Door RL', 'Anim_Door_RL'),
                    ('Door RR', 'Anim_Door_RR'),
                    ('Hood', 'Anim_Hood'),
                    ('Trunk', 'Anim_Trunk'),
                    ('Port', 'Anim_ChargePort'),
                  ])
                    _chip(label, _state.part(anim) > 0, (v) {
                      _set(_state.withPart(anim, v ? 1 : 0), '$anim $v');
                    }),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('Windows  '),
                  SegmentedButton<double>(
                    segments: [
                      for (final f in _kWindowSteps)
                        ButtonSegment(value: f, label: Text('$f')),
                    ],
                    selected: {_state.part('Anim_Window_FL')},
                    onSelectionChanged: (s) {
                      var next = _state;
                      for (final w in ['FL', 'FR', 'RL', 'RR']) {
                        next = next.withPart('Anim_Window_$w', s.first);
                      }
                      _set(next, 'windows ${s.first}');
                    },
                  ),
                ],
              ),
              _section('4 Lights, charging'),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _chip('Lights', _state.lightsOn, (v) {
                    _set(_state.copyWith(lightsOn: v), 'lights $v');
                  }),
                  _chip('Hazards', _state.hazards, (v) {
                    _set(_state.copyWith(hazards: v), 'hazards $v');
                  }),
                  _chip('Power flow', _state.powerFlow, (v) {
                    _set(_state.copyWith(powerFlow: v), 'power flow $v');
                  }),
                ],
              ),
              const SizedBox(height: 6),
              SegmentedButton<Cable>(
                segments: const [
                  ButtonSegment(value: Cable.none, label: Text('No cable')),
                  ButtonSegment(value: Cable.l2, label: Text('L2')),
                  ButtonSegment(value: Cable.dc, label: Text('DC')),
                ],
                selected: {_state.cable},
                onSelectionChanged: (s) {
                  _set(
                    _state.copyWith(cable: s.first),
                    'cable ${s.first.name}',
                  );
                },
              ),
              _section('5 Paint'),
              Wrap(
                spacing: 8,
                children: [
                  for (final MapEntry(key: name, value: color)
                      in _kPaints.entries)
                    ChoiceChip(
                      avatar: CircleAvatar(backgroundColor: color),
                      label: Text(name),
                      selected: _state.paint == color,
                      onSelected: (_) {
                        _set(_state.copyWith(paint: color), 'paint $name');
                      },
                    ),
                ],
              ),
              _section('6–7 Layering and box'),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _chip('Flutter under', _under, (v) {
                    widget.log.add('under $v');
                    setState(() => _under = v);
                  }),
                  _chip('Flutter over', _over, (v) {
                    widget.log.add('over $v');
                    setState(() => _over = v);
                  }),
                  _chip('Tall box', _tall, (v) {
                    widget.log.add('tall $v');
                    setState(() => _tall = v);
                  }),
                  _chip('Narrow box', _narrow, (v) {
                    widget.log.add('narrow $v');
                    setState(() => _narrow = v);
                  }),
                  _chip('Resize loop', _resizeTimer != null, _toggleResizeLoop),
                  ActionChip(
                    avatar: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                    label: const Text('Theme'),
                    onPressed: widget.onToggleTheme,
                  ),
                ],
              ),
              if (widget.tuning.isNotEmpty) _section('Tuning'),
              for (final knob in widget.tuning)
                Row(
                  children: [
                    SizedBox(width: 110, child: Text(knob.name)),
                    Expanded(
                      child: Slider(
                        min: knob.min,
                        max: knob.max,
                        value: _tuning[knob.name]!,
                        onChanged: (v) =>
                            setState(() => _tuning[knob.name] = v),
                        onChangeEnd: (v) => widget.log.add(
                          'tune ${knob.name} = ${v.toStringAsFixed(2)}',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(_tuning[knob.name]!.toStringAsFixed(2)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(title, style: Theme.of(context).textTheme.labelLarge),
  );

  Widget _chip(String label, bool selected, ValueChanged<bool> onSelected) =>
      FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
      );
}

/// The hero's box: optional Flutter content under the renderer (stripes and
/// text, so transparency is obvious) and over it (a header strip and a frosted
/// panel, like the dashboard's tile layer).
class _HeroBox extends StatelessWidget {
  const _HeroBox({
    required this.under,
    required this.over,
    required this.child,
  });

  final bool under;
  final bool over;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.surface),
          if (under) ...[
            CustomPaint(
              painter: _StripesPainter(scheme.primary.withValues(alpha: 0.12)),
            ),
            Center(
              child: Text(
                'FLUTTER UNDER',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: scheme.primary.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
          child,
          if (over) ...[
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                height: 28,
                color: scheme.primaryContainer.withValues(alpha: 0.7),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 8),
                child: const Text('Header over the hero'),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    color: scheme.surface.withValues(alpha: 0.4),
                    alignment: Alignment.center,
                    child: const Text('Frosted tile over the 3D view'),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StripesPainter extends CustomPainter {
  _StripesPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 10;
    for (var x = -size.height; x < size.width; x += 28) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) => old.color != color;
}

// ── Grid screen (item 8) ─────────────────────────────────────────────────────

class _GridScreen extends StatefulWidget {
  const _GridScreen({
    required this.builder,
    required this.log,
    required this.metrics,
  });

  final HeroRendererBuilder builder;
  final SpikeLog log;
  final SpikeMetrics metrics;

  @override
  State<_GridScreen> createState() => _GridScreenState();
}

class _GridScreenState extends State<_GridScreen> {
  final _scroll = ScrollController();
  var _viewers = 1;
  var _scrolling = false;

  static const _tiles = 30;

  /// Tile indices that hold a viewer, spread through the grid.
  List<int> get _viewerSlots => [for (var i = 0; i < _viewers; i++) 1 + i * 5];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _autoScroll() async {
    if (_scrolling || !_scroll.hasClients) return;
    setState(() => _scrolling = true);
    widget.metrics.resetJank();
    widget.log.add('grid auto-scroll: start ($_viewers viewers)');
    final end = _scroll.position.maxScrollExtent;
    for (var i = 0; i < 2 && mounted; i++) {
      await _scroll.animateTo(
        end,
        duration: const Duration(seconds: 3),
        curve: Curves.easeInOut,
      );
      await _scroll.animateTo(
        0,
        duration: const Duration(seconds: 3),
        curve: Curves.easeInOut,
      );
    }
    widget.log.add('grid auto-scroll: done  ${widget.metrics.summary()}');
    if (mounted) setState(() => _scrolling = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slots = _viewerSlots;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              const Text('Viewers '),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('0')),
                  ButtonSegment(value: 1, label: Text('1')),
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 4, label: Text('4')),
                ],
                selected: {_viewers},
                onSelectionChanged: (s) {
                  widget.log.add('grid viewers: ${s.first}');
                  setState(() => _viewers = s.first);
                },
              ),
              const Spacer(),
              IconButton.filled(
                onPressed: _scrolling ? null : _autoScroll,
                icon: const Icon(Icons.swap_vert),
                tooltip: 'Auto-scroll and measure',
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: _tiles,
            itemBuilder: (context, i) {
              final viewerIndex = slots.indexOf(i);
              return Card.filled(
                clipBehavior: Clip.antiAlias,
                child: viewerIndex < 0
                    ? Center(child: Text('Tile $i'))
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          widget.builder(
                            context,
                            HeroRendererConfig(
                              state: HeroSceneState(
                                rearView: viewerIndex.isOdd,
                                lightsOn: true,
                              ),
                              model: SpikeModel.meshopt,
                              isDark: isDark,
                              compact: true,
                              log: widget.log.add,
                            ),
                          ),
                          Positioned(
                            left: 8,
                            top: 6,
                            child: Text(
                              'Car view $viewerIndex',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Log and metrics ──────────────────────────────────────────────────────────

class _LogScreen extends StatelessWidget {
  const _LogScreen({required this.log});

  final SpikeLog log;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
        children: [
          for (final line in log.lines)
            Text(
              line,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class _MetricsBadge extends StatelessWidget {
  const _MetricsBadge({required this.metrics});

  final SpikeMetrics metrics;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: metrics,
        builder: (context, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xC0000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Text(
              '${metrics.fps.toStringAsFixed(0)} fps  '
              'raster ${metrics.avgRasterMs.toStringAsFixed(1)}/'
              '${metrics.worstRasterMs.toStringAsFixed(1)}  '
              'jank ${metrics.jankFrames}/${metrics.totalFrames}\n'
              'rss ${metrics.rssMb} MB  peak ${metrics.peakRssMb}',
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 10,
                fontFamily: 'monospace',
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
