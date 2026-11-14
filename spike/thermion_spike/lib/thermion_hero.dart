import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hero_harness/hero_harness.dart';
import 'package:material_ui/material_ui.dart';
// The spike needs its own texture hook (see [_prepareTexture]), which the
// public widgets don't offer.
// ignore: implementation_imports
import 'package:thermion_flutter/src/platform/src/platform_texture_descriptor.dart';
// ignore: implementation_imports
import 'package:thermion_flutter/src/widgets/src/thermion_widget_internal/surface_widget_builder.dart';
import 'package:thermion_flutter/thermion_flutter.dart' as t;

/// Sliders shown in the checklist's Tuning section.
const kThermionTuning = [
  TuningKnob('ibl lux', 0, 80000, 30000),
  TuningKnob('sun lux', 0, 200000, 60000),
  TuningKnob('emissive x', 0, 0.5, 0.05),
  // Power-flow strength as a multiple of app.js's maxIntensity (5).
  TuningKnob('flow x', 0, 2, 1),
  TuningKnob('uv scroll', 0, 1, 1),
  // 1: the texture only grows, the box crops it and the frustum follows
  // (no reallocation while resizing). 0: Thermion's own resize.
  TuningKnob('grow-only', 0, 1, 1),
  // Thermion's native frame source runs at 60 fps by default in release
  // builds, which drops ticks on a 120 Hz screen. 0 = unlimited.
  TuningKnob('target fps', 0, 120, 120),
  // When only the power flow or hazards move.
  TuningKnob('ambient fps', 10, 120, 30),
];

const _kFrontTheta = 45 * math.pi / 180;
const _kRearTheta = 225 * math.pi / 180;
const _kPhi = 60 * math.pi / 180;
const _kRadius = 10.0;

/// Visible height of the orthographic frustum, and the narrowest width it may
/// have before the height grows so the car still fits.
const _kFrustumHeight = 6.0;
const _kMinFrustumWidth = 6.6;

const _kL2Layer = t.VisibilityLayers.LAYER_1;
const _kDcLayer = t.VisibilityLayers.LAYER_2;

/// A material's target look: base colour (null keeps the model's), emissive
/// colour and an intensity on the Three.js scale (multiplied by the
/// `emissive x` knob for Filament).
typedef _Look = ({int? color, int emissive, double intensity});

/// The E-GMP hero rendered by Thermion (Filament). Same behaviour as
/// `web_3d/src/app.js`: Flutter gives target values, this widget animates.
class ThermionHero extends StatefulWidget {
  const ThermionHero({super.key, required this.config});

  final HeroRendererConfig config;

  @override
  State<ThermionHero> createState() => _ThermionHeroState();
}

class _ThermionHeroState extends State<ThermionHero>
    with SingleTickerProviderStateMixin {
  t.ThermionViewer? _viewer;
  t.ThermionAsset? _asset;
  t.ThermionEntity? _sun;
  late final Ticker _ticker = createTicker(_onTick);
  Future<void>? _init;
  var _disposed = false;

  final _animIndex = <String, int>{};
  final _animDuration = <String, double>{};
  final _parts = <String, double>{};

  /// Material name → its instances, resolved through [GlbIndex].
  final _materials = <String, List<t.MaterialInstance>>{};
  final _appliedLooks = <String, _Look>{};
  final _loggedParams = <String>{};

  var _theta = _kFrontTheta;

  /// Allocated texture, in physical pixels.
  Size _textureSize = const Size(1, 1);

  /// Visible box and grow-only allocation, in physical pixels.
  Size _box = Size.zero;
  Size _alloc = Size.zero;
  var _projectionQueued = false;
  bool get _growOnly => _config.tune('grow-only', 1) >= 0.5;
  Cable? _appliedCable;
  int? _appliedPaint;
  double? _appliedIbl;
  double? _appliedSun;
  int? _appliedFps;
  var _ambient = false;

  var _pulse = 0.0;
  var _scrollU = 0.0;
  var _blinkElapsed = 0.0;
  var _blinkOn = false;
  var _hazardsWere = false;

  Duration? _lastTick;
  var _stepping = false;
  var _carriedDt = 0.0;

  // Per-animation counters, logged when it settles.
  var _ticks = 0;
  var _steps = 0;
  var _skipped = 0;
  var _stepMsTotal = 0.0;
  var _stepMsMax = 0.0;
  double? _resumeMs;
  var _rendering = true;
  Timer? _pauseTimer;
  final _startup = Stopwatch();

  HeroRendererConfig get _config => widget.config;

  void _log(String message) {
    if (!_config.compact || message.startsWith('!')) {
      _config.log('thermion${_config.compact ? '(tile)' : ''}: $message');
    }
  }

  @override
  void initState() {
    super.initState();
    _init = _start();
  }

  @override
  void didUpdateWidget(ThermionHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.state != _config.state ||
        oldWidget.config.tuning != _config.tuning) {
      _wake();
    }
    if (!oldWidget.config.pauseWhenIdle && _config.pauseWhenIdle) _wake();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _pauseTimer?.cancel();
    unawaited(_tearDown());
    super.dispose();
  }

  Future<void> _tearDown() async {
    try {
      await _init;
    } catch (_) {}
    final viewer = _viewer;
    _viewer = null;
    if (viewer == null) return;
    try {
      await t.ThermionFlutterPlugin.instance.destroyTextureForView(viewer.view);
    } finally {
      await viewer.dispose();
      await t.ThermionFlutterPlugin.instance.onViewerDisposed(viewer.view);
    }
  }

  // ── Start-up ───────────────────────────────────────────────────────────────

  Future<void> _start() async {
    _startup.start();
    try {
      final viewer = await t.ThermionFlutterPlugin.createViewer();
      if (_disposed) {
        await viewer.dispose();
        return;
      }
      _viewer = viewer;
      _log('viewer created at ${_startup.elapsedMilliseconds} ms');

      // Transparent background: clear to zero alpha and blend the view.
      await viewer.view.setBlendMode(t.BlendMode.transparent);
      await t.FilamentApp.instance!.setClearOptions(0, 0, 0, 0, clear: true);
      await viewer.setPostProcessing(true);
      await viewer.setAntiAliasing(false, true, false);
      await _applyLighting();
      if (mounted) setState(() {});

      final data = await rootBundle.load(_config.model.assetKey);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final index = GlbIndex.parse(bytes);
      _log(
        '${_config.model.label} model read (${bytes.length ~/ 1024} KB) at '
        '${_startup.elapsedMilliseconds} ms, extensions ${index.extensionsUsed}',
      );

      final loadStart = _startup.elapsedMilliseconds;
      final asset = await viewer.loadGltfFromBuffer(bytes);
      if (_disposed) return;
      _asset = asset;
      _log('glTF loaded in ${_startup.elapsedMilliseconds - loadStart} ms');

      final names = await asset.getGltfAnimationNames();
      for (var i = 0; i < names.length; i++) {
        _animIndex[names[i]] = i;
        _animDuration[names[i]] = await asset.getGltfAnimationDuration(i);
      }
      _log('${names.length} animations: ${names.join(', ')}');

      await _resolveMaterials(asset, index);
      await _assignCableLayers(asset, index);

      // Snap to the current state before the first frame, like the first
      // push in app.js.
      _snapToState();
      await _step(0, instant: true);
      _log('ready at ${_startup.elapsedMilliseconds} ms');
      _wake();
    } catch (e, st) {
      _log('! start-up failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> _applyLighting() async {
    final viewer = _viewer;
    if (viewer == null) return;
    final ibl = _config.tune('ibl lux', 30000);
    if (ibl != _appliedIbl) {
      _appliedIbl = ibl;
      await viewer.loadIbl('assets/default_env_ibl.ktx', intensity: ibl);
    }
    final sun = _config.tune('sun lux', 60000);
    if (sun != _appliedSun) {
      _appliedSun = sun;
      if (_sun != null) await viewer.removeLight(_sun!);
      _sun = await viewer.addDirectLight(
        t.DirectLight.sun(
          intensity: sun,
          castShadows: false,
          direction: t.Vector3(-10, -20, -10).normalized(),
        ),
      );
    }
  }

  Future<void> _resolveMaterials(t.ThermionAsset asset, GlbIndex index) async {
    final entities = await asset.getChildEntities();
    final names = await asset.getChildEntityNames();
    final byName = <String, List<t.ThermionEntity>>{};
    for (var i = 0; i < entities.length; i++) {
      final name = names[i];
      if (name != null) byName.putIfAbsent(name, () => []).add(entities[i]);
    }

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
    final missing = <String>[];
    for (final material in wanted) {
      final refs = index.materials[material] ?? const [];
      final instances = <t.MaterialInstance>[];
      for (final ref in refs) {
        for (final entity in byName[ref.entityName] ?? const <int>[]) {
          // Not asset.getMaterialInstanceAt: in 0.7.0 it ignores `index`
          // and always returns primitive 0.
          instances.add(
            await t.FilamentApp.instance!.getMaterialInstanceAt(
              entity,
              ref.primitive,
            ),
          );
        }
      }
      if (instances.isEmpty) missing.add(material);
      _materials[material] = instances;
    }
    _log(
      'materials resolved: ${_materials.entries.where((e) => e.value.isNotEmpty).length}/'
      '${wanted.length}${missing.isEmpty ? '' : ', missing $missing'} '
      '(${entities.length} entities, ${byName.length} named)',
    );
  }

  Future<void> _assignCableLayers(t.ThermionAsset asset, GlbIndex index) async {
    final names = await asset.getChildEntityNames();
    final entities = await asset.getChildEntities();
    for (final (node, layer) in [
      ('Charger_L2', _kL2Layer),
      ('Charger_DC', _kDcLayer),
    ]) {
      final meshes = index.nodeMeshes[node] ?? const [];
      var count = 0;
      for (var i = 0; i < entities.length; i++) {
        if (meshes.contains(names[i])) {
          await asset.setVisibilityLayer(entities[i], layer);
          count++;
        }
      }
      _log('$node: $count entities on ${layer.name}');
    }
  }

  void _snapToState() {
    final s = _config.state;
    _theta = s.rearView ? _kRearTheta : _kFrontTheta;
    for (final name in _animIndex.keys) {
      _parts[name] = _target(name, s);
    }
    _pulse = s.powerFlow ? 1 : 0;
  }

  /// Target position of an animation: the harness's parts plus the cable
  /// connect animations, which follow the cable.
  double _target(String name, HeroSceneState s) => switch (name) {
    'Anim_Connect_L2' => s.cable == Cable.l2 ? 1 : 0,
    'Anim_Connect_DC' => s.cable == Cable.dc ? 1 : 0,
    _ => s.part(name),
  };

  // ── Texture and camera ─────────────────────────────────────────────────────

  /// Replaces ThermionWidget's texture hook, which resets the camera to a
  /// perspective lens on every (re)allocation.
  Future<void> _prepareTexture(PlatformTextureDescriptor descriptor) async {
    final viewer = _viewer;
    if (viewer == null) return;
    _textureSize = Size(
      descriptor.width.toDouble(),
      descriptor.height.toDouble(),
    );
    await _applyProjection();
    await viewer.view.setViewport(descriptor.width, descriptor.height);
    _log('texture ${descriptor.width}x${descriptor.height}');
    _wake();
  }

  /// Frames the car in the visible box ([_box]); in grow-only mode the
  /// texture can be larger (centred, cropped by the box), so the frustum is
  /// widened to cover all of it at the same scale.
  Future<void> _applyProjection() async {
    final viewer = _viewer;
    if (viewer == null) return;
    final box = _growOnly && !_box.isEmpty ? _box : _textureSize;
    final aspect = box.width / box.height;
    final boxHeight = math.max(_kFrustumHeight, _kMinFrustumWidth / aspect);
    final unitsPerPixel = boxHeight / box.height;
    final width = _textureSize.width * unitsPerPixel;
    final height = _textureSize.height * unitsPerPixel;
    final camera = await viewer.view.getCamera();
    await camera.setProjection(
      t.Projection.Orthographic,
      -width / 2,
      width / 2,
      -height / 2,
      height / 2,
      0.1,
      100,
    );
  }

  Future<void> _applyCamera() async {
    final viewer = _viewer;
    if (viewer == null) return;
    final camera = await viewer.view.getCamera();
    // Same spherical convention as three.js setFromSphericalCoords.
    final position = t.Vector3(
      _kRadius * math.sin(_kPhi) * math.sin(_theta),
      _kRadius * math.cos(_kPhi),
      _kRadius * math.sin(_kPhi) * math.cos(_theta),
    );
    await camera.lookAt(
      position,
      focus: t.Vector3.zero(),
      up: t.Vector3(0, 1, 0),
    );
  }

  // ── Animation loop ─────────────────────────────────────────────────────────

  void _wake() {
    if (_asset == null || _disposed) return;
    // Something changed: back to full rate until the next step decides.
    _ambient = false;
    _applyFps();
    _pauseTimer?.cancel();
    if (!_rendering) {
      _rendering = true;
      final watch = Stopwatch()..start();
      unawaited(
        _viewer
            ?.setRendering(true)
            .then((_) => _resumeMs = watch.elapsedMicroseconds / 1000),
      );
    }
    if (!_ticker.isActive) {
      _lastTick = null;
      _carriedDt = 0;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == null
        ? 0.0
        : (elapsed - _lastTick!).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _ticks++;
    // Skip a frame while the previous one's FFI calls are still in flight,
    // keeping its time for the next step.
    _carriedDt += dt;
    // Ambient motion only: step at the ambient rate, not every vsync.
    if (_ambient &&
        _carriedDt < 1 / _config.tune('ambient fps', 30).clamp(10, 120)) {
      return;
    }
    if (_stepping) {
      _skipped++;
      return;
    }
    _stepping = true;
    final stepDt = math.min(_carriedDt, 0.1);
    _carriedDt = 0;
    final watch = Stopwatch()..start();
    _step(stepDt)
        .then((moving) {
          _stepping = false;
          final ms = watch.elapsedMicroseconds / 1000;
          _stepMsTotal += ms;
          _stepMsMax = math.max(_stepMsMax, ms);
          _steps++;
          if (!moving && !_disposed) _settle();
        })
        .catchError((Object e) {
          _stepping = false;
          _log('! step failed: $e');
        });
  }

  /// Stops the ticker, and rendering when [HeroRendererConfig.pauseWhenIdle],
  /// once nothing moves. Rendering stops a little later so the last change
  /// reaches the texture.
  void _settle() {
    _ticker.stop();
    if (_steps > 3) {
      _log(
        'settled: $_ticks ticks, $_steps steps, $_skipped skipped, step avg '
        '${(_stepMsTotal / _steps).toStringAsFixed(1)} max '
        '${_stepMsMax.toStringAsFixed(1)} ms, resumed '
        '${_resumeMs?.toStringAsFixed(0) ?? '-'} ms after wake',
      );
    }
    _ticks = _steps = _skipped = 0;
    _stepMsTotal = _stepMsMax = 0;
    _resumeMs = null;
    if (!_config.pauseWhenIdle) return;
    _pauseTimer?.cancel();
    _pauseTimer = Timer(const Duration(milliseconds: 250), () {
      if (_disposed || _ticker.isActive) return;
      _rendering = false;
      unawaited(_viewer?.setRendering(false));
      _log('idle: rendering paused');
    });
  }

  /// Advances every tween by [dt] seconds and pushes what changed. Returns
  /// whether anything is still moving.
  Future<bool> _step(double dt, {bool instant = false}) async {
    final asset = _asset;
    if (asset == null) return false;
    final s = _config.state;
    var moving = false;
    final calls = <Future<void>>[];

    await _applyLighting();

    // Camera glide: the same easing as app.js (5% per 60 Hz frame).
    final targetTheta = s.rearView ? _kRearTheta : _kFrontTheta;
    if (instant || (targetTheta - _theta).abs() > 0.001) {
      final k = instant ? 1.0 : 1 - math.pow(0.95, dt * 60).toDouble();
      _theta += (targetTheta - _theta) * k;
      if ((targetTheta - _theta).abs() <= 0.001) _theta = targetTheta;
      calls.add(_applyCamera());
      moving = moving || _theta != targetTheta;
    }

    // Part animations, played at their own speed towards the target.
    for (final MapEntry(key: name, value: index) in _animIndex.entries) {
      final duration = _animDuration[name]!;
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
      // A job-thread round trip each: queue them all, await once below.
      calls.add(asset.setGltfAnimationTime(index, next * duration));
      moving = moving || next != target;
    }

    // Cables: shown or hidden by layer. Filament can't fade an opaque
    // material, so this is a hard switch where app.js fades.
    if (_appliedCable != s.cable) {
      _appliedCable = s.cable;
      await _viewer!.view.setLayerVisibility(_kL2Layer, s.cable == Cable.l2);
      await _viewer!.view.setLayerVisibility(_kDcLayer, s.cable == Cable.dc);
    }

    // Paint.
    final paint = s.paint.toARGB32();
    if (_appliedPaint != paint) {
      _appliedPaint = paint;
      for (final mi in _materials['CarPaint']!) {
        await _setFloat4(mi, 'baseColorFactor', _linear(paint), 1);
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
    await _applyLooks(_looks(s));

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
      for (final mi in _materials['Mat_PowerFlow']!) {
        await _setFloat(mi, 'emissiveStrength', strength);
        if (_config.tune('uv scroll', 1) >= 0.5) {
          await _setMat3(
            mi,
            'emissiveUvMatrix',
            // The ubershader does `vec3(uv, 1.0) * emissiveUvMatrix` (row
            // vector), so the translation goes in the third row.
            t.Matrix3.columns(
              t.Vector3(1, 0, _scrollU),
              t.Vector3(0, 1, 0),
              t.Vector3(0, 0, 1),
            ),
          );
        }
      }
      // `_pulse != pulseTarget` too: the first tick has dt 0, so a fade-in
      // that hasn't started yet still counts as moving.
      moving = moving || _pulse != pulseTarget;
    }

    // Only the power-flow scroll or the hazard blink left: render slower.
    _ambient = !moving && (_pulse > 0 || s.hazards);
    _applyFps();

    await Future.wait(calls);
    return moving || _ambient;
  }

  /// Thermion's render rate: [_ambient] runs at 'ambient fps', anything
  /// else at 'target fps'. Snapped to steps of 10 so a slider doesn't spam.
  void _applyFps() {
    final knob = _ambient ? 'ambient fps' : 'target fps';
    final fps = (_config.tune(knob, _ambient ? 30 : 120) / 10).round() * 10;
    if (fps == _appliedFps) return;
    _appliedFps = fps;
    t.FilamentApp.instance!.setTargetFramerate(fps);
    _log('target fps $fps${_ambient ? ' (ambient)' : ''}');
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

  Future<void> _applyLooks(Map<String, _Look> looks) async {
    final scale = _config.tune('emissive x', 0.05);
    for (final MapEntry(key: name, value: look) in looks.entries) {
      final key = (
        color: look.color,
        emissive: look.emissive,
        intensity: look.intensity * scale,
      );
      if (_appliedLooks[name] == key) continue;
      _appliedLooks[name] = key;
      for (final mi in _materials[name]!) {
        if (look.color != null) {
          await _setFloat4(mi, 'baseColorFactor', _linear(look.color!), 1);
        }
        await _setFloat3(mi, 'emissiveFactor', _linear(look.emissive));
        await _setFloat(mi, 'emissiveStrength', key.intensity);
      }
    }
  }

  // ── Material parameters ────────────────────────────────────────────────────
  // Filament aborts on a wrong parameter name or type, so each one is logged
  // before its first use: a native crash then shows which one in logcat.

  void _firstUse(String param) {
    if (_loggedParams.add(param)) _config.log('thermion: first set of $param');
  }

  Future<void> _setFloat(t.MaterialInstance mi, String name, double v) {
    _firstUse(name);
    return mi.setParameterFloat(name, v);
  }

  Future<void> _setFloat3(t.MaterialInstance mi, String name, t.Vector3 v) {
    _firstUse(name);
    return mi.setParameterFloat3(name, v.x, v.y, v.z);
  }

  Future<void> _setFloat4(
    t.MaterialInstance mi,
    String name,
    t.Vector3 v,
    double a,
  ) {
    _firstUse(name);
    return mi.setParameterFloat4(name, v.x, v.y, v.z, a);
  }

  Future<void> _setMat3(t.MaterialInstance mi, String name, t.Matrix3 m) {
    _firstUse(name);
    return mi.setParameterMat3(name, m);
  }

  static t.Vector3 _linear(int rgb) {
    double channel(int shift) {
      final c = ((rgb >> shift) & 0xff) / 255;
      return c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return t.Vector3(channel(16), channel(8), channel(0));
  }

  static double _ease(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

  // ── Widget ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final viewer = _viewer;
    if (viewer == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final surface = t.ThermionWidgetInternal(
      view: viewer.view,
      surfaceWidgetBuilder: surfaceWidgetBuilder,
      onTexturePreparing: _prepareTexture,
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest * dpr;
        if (box != _box) {
          _box = box;
          _queueProjection();
        }
        if (!_growOnly) return surface;
        // The texture only grows: shrinking the box crops it instead of
        // reallocating, which is what stretches and flashes black.
        _alloc = Size(
          math.max(_alloc.width, box.width),
          math.max(_alloc.height, box.height),
        );
        return ClipRect(
          child: OverflowBox(
            minWidth: _alloc.width / dpr,
            maxWidth: _alloc.width / dpr,
            minHeight: _alloc.height / dpr,
            maxHeight: _alloc.height / dpr,
            child: surface,
          ),
        );
      },
    );
  }

  /// Re-frames the camera for a new box size once this frame's layout is
  /// done, and renders until it has settled.
  void _queueProjection() {
    if (_projectionQueued) return;
    _projectionQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _projectionQueued = false;
      if (_disposed) return;
      unawaited(_applyProjection());
      _wake();
    });
  }
}
