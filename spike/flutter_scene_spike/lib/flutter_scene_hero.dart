import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';
import 'package:hero_harness/hero_harness.dart';
import 'package:material_ui/material_ui.dart' hide Material;
import 'package:vector_math/vector_math.dart' as vm;

/// Sliders shown in the checklist's Tuning section.
const kFlutterSceneTuning = [
  TuningKnob('env intensity', 0, 3, 1),
  TuningKnob('sun intensity', 0, 10, 3),
  // Three.js intensities (50 for headlights) times this.
  TuningKnob('emissive x', 0, 0.2, 0.02),
  // Power-flow strength as a multiple of app.js's maxIntensity (5).
  TuningKnob('flow x', 0, 2, 1),
  // When only the power flow or hazards move.
  TuningKnob('ambient fps', 10, 120, 30),
  // 1: the build hook's .fsceneb (loadScene). 0: runtime glTF import.
  // Read at start-up: Remount after changing it.
  TuningKnob('build-time import', 0, 1, 1),
];

const _kFrontTheta = 45 * math.pi / 180;
const _kRearTheta = 225 * math.pi / 180;
const _kPhi = 60 * math.pi / 180;
const _kRadius = 10.0;

/// A material's target look: base colour (null keeps the model's), emissive
/// colour and an intensity on the Three.js scale (times `emissive x`).
typedef _Look = ({int? color, int emissive, double intensity});

/// The E-GMP hero rendered by flutter_scene (Flutter GPU). Same behaviour as
/// `web_3d/src/app.js`: Flutter gives target values, this widget animates.
class FlutterSceneHero extends StatefulWidget {
  const FlutterSceneHero({super.key, required this.config});

  final HeroRendererConfig config;

  @override
  State<FlutterSceneHero> createState() => _FlutterSceneHeroState();
}

class _FlutterSceneHeroState extends State<FlutterSceneHero> {
  final _scene = Scene();
  Node? _model;
  final _startup = Stopwatch()..start();
  var _disposed = false;

  /// Animation name → its clip, bound to the one node it drives so each has
  /// its own player (clips sharing a player get their weights normalized).
  final _clips = <String, AnimationClip>{};
  final _durations = <String, double>{};
  final _parts = <String, double>{};

  final _materials = <String, List<PhysicallyBasedMaterial>>{};
  final _appliedLooks = <String, _Look>{};
  Node? _l2;
  Node? _dc;

  var _theta = _kFrontTheta;

  /// Whether the model came from the build hook's .fsceneb.
  var _buildTime = true;
  int? _appliedPaint;
  double? _appliedEnv;
  double? _appliedSun;

  var _pulse = 0.0;
  var _scrollU = 0.0;
  var _blinkElapsed = 0.0;
  var _blinkOn = false;
  var _hazardsWere = false;

  /// Ticking while anything moves; SceneView stops its ticker otherwise.
  var _animating = true;
  var _ambient = false;
  Duration? _lastElapsed;

  // Per-animation counters, logged when it settles.
  var _ticks = 0;
  var _stepUsTotal = 0;
  var _stepUsMax = 0;
  final _sinceWake = Stopwatch();
  double? _firstTickMs;

  HeroRendererConfig get _config => widget.config;

  void _log(String message) {
    if (!_config.compact || message.startsWith('!')) {
      _config.log('scene${_config.compact ? '(tile)' : ''}: $message');
    }
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(FlutterSceneHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.state != _config.state ||
        oldWidget.config.tuning != _config.tuning ||
        oldWidget.config.pauseWhenIdle != _config.pauseWhenIdle) {
      _wake();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scene.dispose();
    super.dispose();
  }

  // ── Start-up ───────────────────────────────────────────────────────────────

  Future<void> _start() async {
    try {
      await Scene.initializeStaticResources();
      _log('static resources at ${_startup.elapsedMilliseconds} ms');

      final load = Stopwatch()..start();
      final Node model;
      _buildTime = _config.tune('build-time import', 1) >= 0.5;
      if (_buildTime) {
        // The same files as the harness, linked under this app's assets/ so
        // the build hook converts them.
        final file = _config.model.assetKey.split('/').last;
        model = await loadScene('assets/models/$file');
        _log(
          '${_config.model.name} .fsceneb loaded in '
          '${load.elapsedMilliseconds} ms',
        );
      } else {
        final data = await rootBundle.load(_config.model.assetKey);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        _log(
          '${_config.model.name} model read (${bytes.length ~/ 1024} KB) at '
          '${_startup.elapsedMilliseconds} ms',
        );
        load.reset();
        model = await Node.fromGlbBytes(
          bytes,
          onWarning: (w) => _log('glTF warning: $w'),
        );
        _log('glTF imported at runtime in ${load.elapsedMilliseconds} ms');
      }
      if (_disposed) return;

      _bindAnimations(model);
      _resolveMaterials(model);
      _l2 = model.getChildByName('Charger_L2');
      _dc = model.getChildByName('Charger_DC');
      _log('cables: L2 ${_l2 != null}, DC ${_dc != null}');

      _scene.add(model);
      _model = model;
      _snapToState();
      _step(0, instant: true);
      _log('ready at ${_startup.elapsedMilliseconds} ms');
      if (mounted) setState(() {});
      _wake();
    } catch (e, st) {
      _log('! start-up failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  void _bindAnimations(Node model) {
    final names = <String>[];
    for (final animation in model.parsedAnimations) {
      final channels = animation.channels;
      final target = channels.isEmpty
          ? null
          : model.getChildByName(channels.first.bindTarget.nodeName);
      if (target == null) {
        _log('! ${animation.name}: no target node');
        continue;
      }
      final clip = target.createAnimationClip(animation)..playing = false;
      _clips[animation.name] = clip;
      _durations[animation.name] = animation.endTime;
      names.add(animation.name);
    }
    _log('${names.length} animations: ${names.join(', ')}');
  }

  void _resolveMaterials(Node model) {
    final wanted = {
      'CarPaint',
      'Headlights',
      'TopDRLs',
      'BottomDRLs',
      'BrakeLight_Bar_Main',
      'BrakeLight_Side_Main',
      'BrakeLight_Side_Base1',
      'MirrorTurnSignals',
      'Mat_PowerFlow',
    };
    final found = <String, Set<PhysicallyBasedMaterial>>{};
    var primitives = 0;
    void visit(Node node) {
      for (final primitive in node.mesh?.primitives ?? const []) {
        primitives++;
        final material = primitive.material;
        if (material is PhysicallyBasedMaterial &&
            wanted.contains(material.name)) {
          found.putIfAbsent(material.name, () => {}).add(material);
        }
      }
      node.children.forEach(visit);
    }

    visit(model);
    for (final name in wanted) {
      _materials[name] = (found[name] ?? const {}).toList();
    }
    final missing = wanted.where((n) => found[n] == null).toList();
    _log(
      'materials resolved: ${found.length}/${wanted.length}'
      '${missing.isEmpty ? '' : ', missing $missing'} ($primitives primitives, '
      '${found.values.fold(0, (n, s) => n + s.length)} instances)',
    );
  }

  void _snapToState() {
    final s = _config.state;
    _theta = s.rearView ? _kRearTheta : _kFrontTheta;
    for (final name in _clips.keys) {
      _parts[name] = _target(name, s);
    }
    _pulse = s.powerFlow ? 1 : 0;
  }

  double _target(String name, HeroSceneState s) => switch (name) {
    'Anim_Connect_L2' => s.cable == Cable.l2 ? 1 : 0,
    'Anim_Connect_DC' => s.cable == Cable.dc ? 1 : 0,
    _ => s.part(name),
  };

  // ── Animation loop ─────────────────────────────────────────────────────────

  void _wake() {
    if (_model == null || _disposed) return;
    _ambient = false;
    if (!_animating) {
      _sinceWake
        ..reset()
        ..start();
      _firstTickMs = null;
    }
    _lastElapsed = null;
    setState(() => _animating = true);
  }

  void _onTick(Duration elapsed, double _) {
    // SceneView keeps its last tick time across a ticker restart, so its
    // first delta after an idle stretch is the whole stretch. Own clock.
    final last = _lastElapsed;
    _lastElapsed = elapsed;
    final dt = last == null ? 0.0 : (elapsed - last).inMicroseconds / 1e6;
    _firstTickMs ??= _sinceWake.elapsedMicroseconds / 1000;

    final watch = Stopwatch()..start();
    final moving = _step(math.min(dt, 0.1));
    final us = watch.elapsedMicroseconds;
    _ticks++;
    _stepUsTotal += us;
    _stepUsMax = math.max(_stepUsMax, us);

    final ambient = !moving && (_pulse > 0 || _config.state.hazards);
    if (ambient != _ambient) {
      _ambient = ambient;
      _log(ambient ? 'ambient: ${_ambientFps.round()} fps' : 'full rate');
      setState(() {});
    }
    if (!moving && !ambient) _settle();
  }

  double get _ambientFps =>
      _config.tune('ambient fps', 30).clamp(10, 120).toDouble();

  void _settle() {
    if (_ticks > 3) {
      _log(
        'settled: $_ticks ticks, step avg '
        '${(_stepUsTotal / _ticks / 1000).toStringAsFixed(2)} max '
        '${(_stepUsMax / 1000).toStringAsFixed(2)} ms, first tick '
        '${_firstTickMs?.toStringAsFixed(0) ?? '-'} ms after wake',
      );
    }
    _ticks = _stepUsTotal = _stepUsMax = 0;
    if (_config.pauseWhenIdle && _animating) {
      setState(() => _animating = false);
      _log('idle: ticking stopped');
    }
  }

  /// Advances every tween by [dt] seconds and writes the scene. Returns
  /// whether anything is still moving. All plain Dart: no native round trip.
  bool _step(double dt, {bool instant = false}) {
    final s = _config.state;
    var moving = false;

    _applyLighting();

    // Camera glide: the same easing as app.js (5% per 60 Hz frame).
    final targetTheta = s.rearView ? _kRearTheta : _kFrontTheta;
    if (instant || (targetTheta - _theta).abs() > 0.001) {
      final k = instant ? 1.0 : 1 - math.pow(0.95, dt * 60).toDouble();
      _theta += (targetTheta - _theta) * k;
      if ((targetTheta - _theta).abs() <= 0.001) _theta = targetTheta;
      moving = moving || _theta != targetTheta;
    }

    // Part animations, played at their own speed towards the target.
    for (final MapEntry(key: name, value: clip) in _clips.entries) {
      final duration = _durations[name]!;
      final target = _target(name, s);
      final current = _parts[name] ?? 0;
      if (!instant && current == target) continue;
      final step = duration > 0 ? dt / duration : 1.0;
      final next = instant
          ? target
          : current < target
          ? math.min(target, current + step)
          : math.max(target, current - step);
      _parts[name] = next;
      clip.seek(next * duration);
      moving = moving || next != target;
    }

    // Cables: shown or hidden. A fade would need blend materials; app.js
    // fades, the spike switches.
    _l2?.visible = s.cable == Cable.l2;
    _dc?.visible = s.cable == Cable.dc;

    // Paint.
    final paint = s.paint.toARGB32();
    if (_appliedPaint != paint) {
      _appliedPaint = paint;
      for (final m in _materials['CarPaint']!) {
        m.baseColorFactor = _linear4(paint, 1);
      }
    }

    // Hazards blink every 500 ms, starting on.
    if (s.hazards != _hazardsWere) {
      _hazardsWere = s.hazards;
      _blinkOn = s.hazards;
      _blinkElapsed = 0;
    } else if (s.hazards) {
      _blinkElapsed += dt;
      if (_blinkElapsed >= 0.5) {
        _blinkElapsed = 0;
        _blinkOn = !_blinkOn;
      }
    }
    _applyLooks(_looks(s));

    // Charging glow: fade the emissive in or out over 500 ms and scroll the
    // texture while it is visible.
    final pulseTarget = s.powerFlow ? 1.0 : 0.0;
    if (_pulse != pulseTarget || _pulse > 0 || instant) {
      _pulse = instant
          ? pulseTarget
          : _pulse < pulseTarget
          ? math.min(pulseTarget, _pulse + dt / 0.5)
          : math.max(pulseTarget, _pulse - dt / 0.5);
      _scrollU = _pulse > 0 ? (_scrollU + dt * 0.18) % 1 : 0;
      final strength = _ease(_pulse) * 5 * _config.tune('flow x', 1);
      for (final m in _materials['Mat_PowerFlow']!) {
        m.emissiveStrength = strength;
        // A fresh transform each time: in-place edits are ignored on the
        // physical-variant path.
        m.emissiveTextureTransform = TextureTransform(
          offset: vm.Vector2(_scrollU, 0),
        );
      }
      moving = moving || _pulse != pulseTarget;
    }
    return moving;
  }

  void _applyLighting() {
    final env = _config.tune('env intensity', 1);
    if (env != _appliedEnv) {
      _appliedEnv = env;
      _scene.environmentIntensity = env;
    }
    final sun = _config.tune('sun intensity', 3);
    if (sun != _appliedSun) {
      _appliedSun = sun;
      // app.js puts the light at (10, 20, 10): direction towards the scene.
      _scene.directionalLight = DirectionalLight(
        direction: vm.Vector3(-10, -20, 10).normalized(),
        intensity: sun,
      );
    }
  }

  /// The looks of the light materials for [s], as in vehicle_3d_viewer.dart.
  Map<String, _Look> _looks(HeroSceneState s) {
    final lights = s.lightsOn ? 0xffffff : 0x000000;
    final lightsIntensity = s.lightsOn ? 50.0 : 0.0;
    final brake = s.lightsOn ? 20.0 : 0.0;
    final hazardOn = s.hazards && _blinkOn;
    return {
      'Headlights': (color: null, emissive: lights, intensity: lightsIntensity),
      'BottomDRLs': (color: null, emissive: lights, intensity: lightsIntensity),
      'BrakeLight_Bar_Main': (
        color: null,
        emissive: 0xff0000,
        intensity: brake,
      ),
      'BrakeLight_Side_Main': (
        color: null,
        emissive: 0xff0000,
        intensity: brake,
      ),
      'TopDRLs': hazardOn
          ? (color: 0xffc400, emissive: 0xffc400, intensity: 50.0)
          : (color: 0xffffff, emissive: lights, intensity: lightsIntensity),
      'MirrorTurnSignals': hazardOn
          ? (color: 0xffc400, emissive: 0xffc400, intensity: 50.0)
          : (color: 0xe7e7e7, emissive: 0x000000, intensity: 0.0),
      'BrakeLight_Side_Base1': (
        color: null,
        emissive: 0x970000,
        intensity: hazardOn ? 20.0 : 0.0,
      ),
    };
  }

  void _applyLooks(Map<String, _Look> looks) {
    final scale = _config.tune('emissive x', 0.02);
    for (final MapEntry(key: name, value: look) in looks.entries) {
      final key = (
        color: look.color,
        emissive: look.emissive,
        intensity: look.intensity * scale,
      );
      if (_appliedLooks[name] == key) continue;
      _appliedLooks[name] = key;
      for (final m in _materials[name]!) {
        if (look.color != null) m.baseColorFactor = _linear4(look.color!, 1);
        m.emissiveFactor = _linear4(look.emissive, 1);
        m.emissiveStrength = key.intensity;
      }
    }
  }

  static vm.Vector4 _linear4(int rgb, double a) {
    double channel(int shift) {
      final c = ((rgb >> shift) & 0xff) / 255;
      return c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return vm.Vector4(channel(16), channel(8), channel(0), a);
  }

  static double _ease(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

  // ── Widget ─────────────────────────────────────────────────────────────────

  /// app.js's spherical camera with Z negated: both import paths convert
  /// glTF's right-handed Z into the engine's left-handed space.
  Camera get _camera => OrthographicCamera(
    projection: OrthographicProjection(
      // At least 6.6 wide and 6 tall, like the app's frustum rule.
      size: const OrthographicSize.contain(6.6, 6),
      far: 100,
    ),
    position: vm.Vector3(
      _kRadius * math.sin(_kPhi) * math.sin(_theta),
      _kRadius * math.cos(_kPhi),
      -_kRadius * math.sin(_kPhi) * math.cos(_theta),
    ),
    target: vm.Vector3.zero(),
  );

  @override
  Widget build(BuildContext context) {
    if (_model == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SceneView(
      _scene,
      cameraBuilder: (_) => _camera,
      autoTick: _animating || !_config.pauseWhenIdle,
      maxFrameRate: _ambient ? _ambientFps : null,
      onTick: _onTick,
    );
  }
}
