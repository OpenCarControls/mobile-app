import 'dart:math' as math;

import 'package:open_car_app/cars/egmp/hero/egmp_scene.dart';

/// Camera angles around the car, in radians: the front driver side, and the
/// rear passenger side where the EV6's charge port is.
const kEgmpFrontTheta = 45 * math.pi / 180;
const kEgmpRearTheta = 225 * math.pi / 180;

/// How long the charging glow takes to fade in or out, in seconds.
const _kFlowFade = 0.5;

/// How fast the glow's texture scrolls, in texture widths per second.
const _kFlowScroll = 0.18;

/// Half a hazard blink, in seconds.
const _kBlinkHalf = 0.5;

/// What a [EgmpMotion.step] changed, for the renderer to push.
class EgmpFrame {
  const EgmpFrame({
    required this.cameraMoved,
    required this.parts,
    required this.flowChanged,
    required this.moving,
    required this.ambient,
  });

  /// [EgmpMotion.theta] changed.
  final bool cameraMoved;

  /// The parts whose position changed, with the new position (0 to 1).
  final Map<String, double> parts;

  /// [EgmpMotion.flowStrength] or [EgmpMotion.scrollU] changed.
  final bool flowChanged;

  /// Something is still on its way to the target.
  final bool moving;

  /// Nothing moves towards a target, but the glow scroll or the hazard blink
  /// runs: the renderer can step at a lower rate.
  final bool ambient;
}

/// The hero's animation state, moved towards an [EgmpScene] one step at a
/// time. Holds no renderer objects, so it is tested on its own.
class EgmpMotion {
  /// [durations] are the glTF animations' lengths in seconds, by name. Parts
  /// play at their own speed: a full open takes the animation's length.
  EgmpMotion({required Map<String, double> durations}) : _durations = durations;

  final Map<String, double> _durations;

  /// Camera angle around the car.
  double theta = kEgmpFrontTheta;

  final _parts = <String, double>{};

  /// The glow's fade, 0 (off) to 1 (on), before easing.
  double _flow = 0;

  /// The glow's texture offset, 0 to 1.
  double scrollU = 0;

  bool blinkOn = false;
  double _blinkElapsed = 0;
  bool _hazards = false;

  /// Current position of a part, 0 to 1.
  double part(String name) => _parts[name] ?? 0;

  /// The glow's strength, 0 to 1, eased.
  double get flowStrength => _ease(_flow);

  /// Advances everything by [dt] seconds towards [scene]. [instant] jumps to
  /// the target (the first frame). [reducedMotion] snaps the camera and shows
  /// the glow without its fade or scroll.
  EgmpFrame step(
    EgmpScene scene,
    double dt, {
    bool instant = false,
    bool reducedMotion = false,
  }) {
    var moving = false;

    // Camera glide: 5% of the way per 60 Hz frame, like the WebView viewer.
    final targetTheta = scene.rearView ? kEgmpRearTheta : kEgmpFrontTheta;
    var cameraMoved = false;
    if (instant || theta != targetTheta) {
      final k = instant || reducedMotion
          ? 1.0
          : 1 - math.pow(0.95, dt * 60).toDouble();
      final before = theta;
      theta += (targetTheta - theta) * k;
      if ((targetTheta - theta).abs() <= 0.001) theta = targetTheta;
      cameraMoved = instant || theta != before;
      moving = theta != targetTheta;
    }

    final parts = <String, double>{};
    for (final MapEntry(key: name, value: duration) in _durations.entries) {
      final target = scene.part(name);
      final current = part(name);
      if (!instant && current == target) continue;
      final delta = duration > 0 ? dt / duration : 1.0;
      final next = instant
          ? target
          : current < target
          ? math.min(target, current + delta)
          : math.max(target, current - delta);
      _parts[name] = next;
      parts[name] = next;
      moving = moving || next != target;
    }

    final flowTarget = scene.powerFlow ? 1.0 : 0.0;
    final flowBefore = _flow;
    final scrollBefore = scrollU;
    if (instant || reducedMotion) {
      _flow = flowTarget;
      scrollU = 0;
    } else {
      _flow = _flow < flowTarget
          ? math.min(flowTarget, _flow + dt / _kFlowFade)
          : math.max(flowTarget, _flow - dt / _kFlowFade);
      scrollU = _flow > 0 ? (scrollU + dt * _kFlowScroll) % 1 : 0;
    }
    final flowChanged =
        instant || _flow != flowBefore || scrollU != scrollBefore;
    // The first tick has dt 0, so a fade that hasn't started still counts.
    moving = moving || _flow != flowTarget;

    // Hazards blink every half second, starting on.
    if (scene.hazards != _hazards) {
      _hazards = scene.hazards;
      blinkOn = scene.hazards;
      _blinkElapsed = 0;
    } else if (scene.hazards) {
      _blinkElapsed += dt;
      while (_blinkElapsed >= _kBlinkHalf) {
        _blinkElapsed -= _kBlinkHalf;
        blinkOn = !blinkOn;
      }
    }

    return EgmpFrame(
      cameraMoved: cameraMoved,
      parts: parts,
      flowChanged: flowChanged,
      moving: moving,
      ambient: !moving && ((_flow > 0 && !reducedMotion) || scene.hazards),
    );
  }

  static double _ease(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
}
