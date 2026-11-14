import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The hero sets its own camera when the texture is (re)allocated, which the
// public ThermionWidget doesn't allow (it resets to a perspective lens).
// ignore: implementation_imports
import 'package:thermion_flutter/src/platform/src/platform_texture_descriptor.dart';
// ignore: implementation_imports
import 'package:thermion_flutter/src/widgets/src/thermion_widget_internal/surface_widget_builder.dart';
import 'package:thermion_flutter/thermion_flutter.dart' as t;

import 'package:open_car_app/cars/egmp/hero/egmp_motion.dart';
import 'package:open_car_app/cars/egmp/hero/egmp_scene.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/widgets/hero/glb_index.dart';
import 'package:open_car_app/widgets/hero/thermion_frame_rate.dart';
import 'package:open_car_app/widgets/hero_placeholder.dart';

const _kModelAsset = 'assets/cars/egmp/2022_kia_ev6.glb';
const _kIblAsset = 'assets/hero/default_env_ibl.ktx';

/// Light intensities, in Filament's physical units (lux). Set on the phone
/// in the renderer spike (#75); the model's light materials still need work.
const _kIblLux = 30000.0;
const _kSunLux = 60000.0;

/// Converts the [EgmpLook] intensities (Three.js scale) to Filament's.
const _kEmissiveScale = 0.05;

/// The glow's emissive strength at full fade, on the Three.js scale.
const _kFlowStrength = 5.0;

/// Render rates: anything moving towards its target, and only the glow
/// scroll or the hazard blink.
const _kMotionFps = 120;
const _kAmbientFps = 30;

/// Camera elevation and distance (the distance only matters for clipping).
const _kPhi = 60 * math.pi / 180;
const _kRadius = 10.0;

/// Visible height of the orthographic frustum, and the narrowest width it may
/// have before the height grows so the car still fits.
const _kFrustumHeight = 6.0;
const _kMinFrustumWidth = 6.6;

/// The cables are on their own layers so they can be shown and hidden.
const _kL2Layer = t.VisibilityLayers.LAYER_1;
const _kDcLayer = t.VisibilityLayers.LAYER_2;

/// How long the car takes to fade in once it has drawn.
const _kFadeIn = Duration(milliseconds: 300);

/// State older than this is shown grayed out.
const _kRecentThreshold = Duration(seconds: 30);

const _kGrayscale = ColorFilter.matrix([
  0.33, 0.59, 0.11, 0, 0, //
  0.33, 0.59, 0.11, 0, 0, //
  0.33, 0.59, 0.11, 0, 0, //
  0, 0, 0, 1, 0, //
]);

bool _isRecent(VehicleSnapshot s) {
  if (s.isStateLive) return true;
  final lastUpdated = s.lastUpdated;
  if (lastUpdated == null) return false;
  return DateTime.now().difference(lastUpdated) < _kRecentThreshold;
}

/// The E-GMP hero: the EV6 model rendered by Thermion (Filament), driven by
/// [snapshot]. It reads no providers and sends nothing (see
/// `docs/ui-hero.md`). Flutter animates: each tick moves [EgmpMotion] and
/// pushes what changed to the engine.
class EgmpHero extends StatefulWidget {
  const EgmpHero({super.key, required this.snapshot});

  final VehicleSnapshot snapshot;

  @override
  State<EgmpHero> createState() => _EgmpHeroState();
}

enum _Phase { starting, ready, failed }

class _EgmpHeroState extends State<EgmpHero>
    with SingleTickerProviderStateMixin {
  t.ThermionViewer? _viewer;
  t.ThermionAsset? _asset;
  EgmpMotion? _motion;
  late final _ticker = createTicker(_onTick);
  Future<void>? _init;
  var _disposed = false;
  var _phase = _Phase.starting;

  /// The view has drawn the current state, so it fades in.
  var _showLive = false;

  late EgmpScene _scene = EgmpScene.fromSnapshot(widget.snapshot);
  var _reducedMotion = false;

  final _animIndex = <String, int>{};
  final _animDuration = <String, double>{};

  /// Material name → its instances, resolved through [GlbIndex].
  final _materials = <String, List<t.MaterialInstance>>{};
  final _appliedLooks = <String, EgmpLook>{};
  EgmpCable? _appliedCable;

  /// Allocated texture, in physical pixels.
  Size _textureSize = const Size(1, 1);

  /// Visible box and the grow-only allocation, in physical pixels.
  Size _box = Size.zero;
  Size _alloc = Size.zero;
  var _projectionQueued = false;

  Duration? _lastTick;
  var _stepping = false;
  var _carriedDt = 0.0;
  var _ambient = false;
  var _rendering = true;
  Timer? _pauseTimer;

  /// Keeps the view mounted when the stale filter wraps it or comes off;
  /// a remount would reallocate the texture.
  final _contentKey = GlobalKey();

  /// Thermion's surface, created once. In 0.7.0 every rebuild during the
  /// first texture allocation schedules another one, which replaces the
  /// texture with a black one 100 ms later; the same instance is never
  /// rebuilt by its parent.
  Widget? _surfaceWidget;

  void _log(String message) => dev.log(message, name: 'EgmpHero');

  @override
  void initState() {
    super.initState();
    _init = _start();
    unawaited(_deleteLegacySnapshots());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != _reducedMotion) {
      _reducedMotion = reduced;
      _wake();
    }
  }

  @override
  void didUpdateWidget(EgmpHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.snapshot, widget.snapshot)) return;
    final scene = EgmpScene.fromSnapshot(widget.snapshot);
    if (scene == _scene) return;
    _scene = scene;
    _wake();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _pauseTimer?.cancel();
    thermionFrameRate.release(this);
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
    final startup = Stopwatch()..start();
    try {
      final viewer = await t.ThermionFlutterPlugin.createViewer();
      if (_disposed) {
        await viewer.dispose();
        return;
      }
      _viewer = viewer;

      // Transparent background: clear to zero alpha and blend the view.
      await viewer.view.setBlendMode(t.BlendMode.transparent);
      await t.FilamentApp.instance!.setClearOptions(0, 0, 0, 0, clear: true);
      await viewer.setPostProcessing(true);
      await viewer.setAntiAliasing(false, true, false);
      await viewer.loadIbl(_kIblAsset, intensity: _kIblLux);
      await viewer.addDirectLight(
        t.DirectLight.sun(
          intensity: _kSunLux,
          castShadows: false,
          direction: t.Vector3(-10, -20, -10).normalized(),
        ),
      );
      if (mounted) setState(() {});

      final data = await rootBundle.load(_kModelAsset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final index = GlbIndex.parse(bytes);
      final asset = await viewer.loadGltfFromBuffer(bytes);
      if (_disposed) return;
      _asset = asset;

      final names = await asset.getGltfAnimationNames();
      for (var i = 0; i < names.length; i++) {
        _animIndex[names[i]] = i;
        _animDuration[names[i]] = await asset.getGltfAnimationDuration(i);
      }
      await _resolveMaterials(asset, index);
      await _assignCableLayers(asset, index);

      // Jump to the current state before the first frame.
      _motion = EgmpMotion(durations: _animDuration);
      await _step(0, instant: true);
      if (_disposed) return;
      _log('ready in ${startup.elapsedMilliseconds} ms');
      setState(() => _phase = _Phase.ready);
      // Let the view draw the state before fading it in. Its texture is
      // black until then, and the fade keeps its first frames on screen
      // nearly invisible.
      Timer(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _showLive = true);
      });
      _wake();
    } catch (e, st) {
      _log('Start-up failed: $e');
      dev.log('$st', name: 'EgmpHero');
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _resolveMaterials(t.ThermionAsset asset, GlbIndex index) async {
    final byName = await _entitiesByName(asset);
    for (final material in [...kEgmpLightMaterials, 'Mat_PowerFlow']) {
      final instances = <t.MaterialInstance>[];
      for (final ref in index.materials[material] ?? const <PrimitiveRef>[]) {
        for (final entity in byName[ref.entityName] ?? const <int>[]) {
          // Not asset.getMaterialInstanceAt: in 0.7.0 it ignores the index
          // and always returns primitive 0, and lights share meshes with
          // glass on this model.
          instances.add(
            await t.FilamentApp.instance!.getMaterialInstanceAt(
              entity,
              ref.primitive,
            ),
          );
        }
      }
      if (instances.isEmpty) _log('Material $material not found');
      _materials[material] = instances;
    }
  }

  /// Entities by name. Unnamed mesh nodes (the meshopt model wraps every
  /// mesh in one) are named after their mesh, as [GlbIndex] expects.
  Future<Map<String, List<t.ThermionEntity>>> _entitiesByName(
    t.ThermionAsset asset,
  ) async {
    final entities = await asset.getChildEntities();
    final names = await asset.getChildEntityNames();
    final byName = <String, List<t.ThermionEntity>>{};
    for (var i = 0; i < entities.length; i++) {
      final name = names[i];
      if (name != null) byName.putIfAbsent(name, () => []).add(entities[i]);
    }
    return byName;
  }

  Future<void> _assignCableLayers(t.ThermionAsset asset, GlbIndex index) async {
    final byName = await _entitiesByName(asset);
    for (final (node, layer) in [
      ('Charger_L2', _kL2Layer),
      ('Charger_DC', _kDcLayer),
    ]) {
      for (final mesh in index.nodeMeshes[node] ?? const <String>[]) {
        for (final entity in byName[mesh] ?? const <int>[]) {
          await asset.setVisibilityLayer(entity, layer);
        }
      }
    }
  }

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
    _wake();
  }

  /// Frames the car in the visible box. The texture can be larger (it only
  /// grows, centred and cropped by the box), so the frustum covers all of it
  /// at the box's scale.
  Future<void> _applyProjection() async {
    final viewer = _viewer;
    if (viewer == null) return;
    final box = _box.isEmpty ? _textureSize : _box;
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

  Future<void> _applyCamera(double theta) async {
    final viewer = _viewer;
    if (viewer == null) return;
    final camera = await viewer.view.getCamera();
    // Same spherical convention as three.js setFromSphericalCoords.
    final position = t.Vector3(
      _kRadius * math.sin(_kPhi) * math.sin(theta),
      _kRadius * math.cos(_kPhi),
      _kRadius * math.sin(_kPhi) * math.cos(theta),
    );
    await camera.lookAt(
      position,
      focus: t.Vector3.zero(),
      up: t.Vector3(0, 1, 0),
    );
  }

  // ── Animation loop ─────────────────────────────────────────────────────────

  void _wake() {
    if (_motion == null || _disposed) return;
    _ambient = false;
    thermionFrameRate.request(this, _kMotionFps);
    _pauseTimer?.cancel();
    if (!_rendering) {
      _rendering = true;
      unawaited(_viewer?.setRendering(true));
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
    // Time of skipped ticks carries into the next step.
    _carriedDt += dt;
    if (_ambient && _carriedDt < 1 / _kAmbientFps) return;
    // The previous step's engine calls are still in flight.
    if (_stepping) return;
    _stepping = true;
    final stepDt = math.min(_carriedDt, 0.1);
    _carriedDt = 0;
    _step(stepDt)
        .then((running) {
          _stepping = false;
          if (!running && !_disposed) _settle();
        })
        .catchError((Object e) {
          _stepping = false;
          _log('Step failed: $e');
        });
  }

  /// Stops the ticker once nothing moves, then rendering a little later so
  /// the last change reaches the texture.
  void _settle() {
    _ticker.stop();
    _pauseTimer?.cancel();
    _pauseTimer = Timer(const Duration(milliseconds: 250), () {
      if (_disposed || _ticker.isActive) return;
      _rendering = false;
      unawaited(_viewer?.setRendering(false));
      thermionFrameRate.release(this);
    });
  }

  /// Advances the motion by [dt] seconds and pushes what changed. Returns
  /// whether the ticker should keep running.
  Future<bool> _step(double dt, {bool instant = false}) async {
    final asset = _asset;
    final motion = _motion;
    final viewer = _viewer;
    if (asset == null || motion == null || viewer == null) return false;
    final scene = _scene;
    final frame = motion.step(
      scene,
      dt,
      instant: instant,
      reducedMotion: _reducedMotion,
    );
    // Each call is a job-thread round trip: queue them all, await once.
    final calls = <Future<void>>[];

    if (frame.cameraMoved) calls.add(_applyCamera(motion.theta));
    for (final MapEntry(key: name, value: position) in frame.parts.entries) {
      calls.add(
        asset.setGltfAnimationTime(
          _animIndex[name]!,
          position * _animDuration[name]!,
        ),
      );
    }

    // Filament can't fade an opaque material, so the cables switch by layer
    // where the WebView viewer faded them.
    if (_appliedCable != scene.cable) {
      _appliedCable = scene.cable;
      calls.add(
        viewer.view.setLayerVisibility(_kL2Layer, scene.cable == EgmpCable.l2),
      );
      calls.add(
        viewer.view.setLayerVisibility(_kDcLayer, scene.cable == EgmpCable.dc),
      );
    }

    final looks = egmpLooks(scene, blinkOn: motion.blinkOn);
    for (final MapEntry(key: name, value: look) in looks.entries) {
      if (_appliedLooks[name] == look) continue;
      _appliedLooks[name] = look;
      final intensity = look.intensity * _kEmissiveScale;
      for (final mi in _materials[name]!) {
        if (look.color != null) {
          calls.add(_setFloat4(mi, 'baseColorFactor', _linear(look.color!)));
        }
        calls.add(_setFloat3(mi, 'emissiveFactor', _linear(look.emissive)));
        calls.add(mi.setParameterFloat('emissiveStrength', intensity));
      }
    }

    if (frame.flowChanged) {
      final strength = motion.flowStrength * _kFlowStrength * _kEmissiveScale;
      for (final mi in _materials['Mat_PowerFlow']!) {
        calls.add(mi.setParameterFloat('emissiveStrength', strength));
        // The ubershader does `vec3(uv, 1.0) * emissiveUvMatrix` (a row
        // vector), so the translation goes in the third row.
        calls.add(
          mi.setParameterMat3(
            'emissiveUvMatrix',
            t.Matrix3.columns(
              t.Vector3(1, 0, motion.scrollU),
              t.Vector3(0, 1, 0),
              t.Vector3(0, 0, 1),
            ),
          ),
        );
      }
    }

    if (frame.ambient != _ambient) {
      _ambient = frame.ambient;
      thermionFrameRate.request(
        this,
        frame.ambient ? _kAmbientFps : _kMotionFps,
      );
    }

    await Future.wait(calls);
    return frame.moving || frame.ambient;
  }

  static Future<void> _setFloat3(
    t.MaterialInstance mi,
    String name,
    t.Vector3 v,
  ) => mi.setParameterFloat3(name, v.x, v.y, v.z);

  static Future<void> _setFloat4(
    t.MaterialInstance mi,
    String name,
    t.Vector3 v,
  ) => mi.setParameterFloat4(name, v.x, v.y, v.z, 1);

  /// An sRGB colour as linear RGB, which Filament's parameters take.
  static t.Vector3 _linear(int rgb) {
    double channel(int shift) {
      final c = ((rgb >> shift) & 0xff) / 255;
      return c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return t.Vector3(channel(16), channel(8), channel(0));
  }

  // ── Widget ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final viewer = _viewer;
    Widget content = Stack(
      key: _contentKey,
      fit: StackFit.expand,
      children: [
        if (_phase == _Phase.failed)
          const HeroPlaceholder()
        // Mounted from the start so the texture is allocated early, but only
        // faded in once it has drawn the car.
        else if (viewer != null)
          AnimatedOpacity(
            opacity: _showLive ? 1 : 0,
            duration: _kFadeIn,
            child: _surface(viewer),
          ),
      ],
    );
    if (!_isRecent(widget.snapshot)) {
      content = ColorFiltered(colorFilter: _kGrayscale, child: content);
    }
    return ExcludeSemantics(child: IgnorePointer(child: content));
  }

  Widget _surface(t.ThermionViewer viewer) {
    final surface = _surfaceWidget ??= t.ThermionWidgetInternal(
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
        // The texture only grows: a smaller box crops it instead of
        // reallocating, which stretches the old frame and flashes black.
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

var _legacyDeleted = false;

/// Removes the WebView viewer's snapshots: PNG files, and the
/// SharedPreferences keys of builds before those.
Future<void> _deleteLegacySnapshots() async {
  if (_legacyDeleted) return;
  _legacyDeleted = true;
  try {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/vehicle_3d',
    );
    if (await dir.exists()) await dir.delete(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    for (final key in const [
      'vehicle_3d_last_frame',
      'vehicle_3d_last_frame_light',
      'vehicle_3d_last_frame_dark',
    ]) {
      await prefs.remove(key);
    }
  } catch (e) {
    dev.log('Failed to delete old snapshots: $e', name: 'EgmpHero');
  }
}
