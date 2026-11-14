import 'package:flutter/widgets.dart';

/// Which charging cable is plugged in.
enum Cable { none, l2, dc }

/// The models the spike can load. Both are the same EV6 export: the
/// meshopt-compressed one the app ships and the uncompressed Blender export.
enum SpikeModel {
  meshopt('packages/hero_harness/assets/models/ev6_meshopt.glb', 'meshopt'),
  raw('packages/hero_harness/assets/models/ev6_raw.glb', 'raw');

  const SpikeModel(this.assetKey, this.label);

  /// Key for `rootBundle.load`.
  final String assetKey;
  final String label;
}

/// Part animations in the model, by glTF animation name.
const kPartAnimations = [
  'Anim_Door_FL',
  'Anim_Door_FR',
  'Anim_Door_RL',
  'Anim_Door_RR',
  'Anim_Window_FL',
  'Anim_Window_FR',
  'Anim_Window_RL',
  'Anim_Window_RR',
  'Anim_Hood',
  'Anim_Trunk',
  'Anim_ChargePort',
];

/// The target state of the hero. Renderers animate towards it: camera glide,
/// part animations and fades happen inside the renderer, as in `app.js`.
@immutable
class HeroSceneState {
  const HeroSceneState({
    this.rearView = false,
    this.parts = const {},
    this.lightsOn = false,
    this.hazards = false,
    this.cable = Cable.none,
    this.powerFlow = false,
    this.paint = const Color(0xFF5B0A02),
  });

  /// Camera at the rear passenger side (charge port view) instead of the
  /// front driver side.
  final bool rearView;

  /// Target position of each part animation, 0 (closed) to 1 (open). Missing
  /// entries are 0. Windows use partial values.
  final Map<String, double> parts;

  final bool lightsOn;
  final bool hazards;
  final Cable cable;

  /// Charging glow: emissive pulse plus a scrolling texture on the cable.
  final bool powerFlow;

  /// Base colour of the `CarPaint` material.
  final Color paint;

  double part(String name) => parts[name] ?? 0;

  HeroSceneState copyWith({
    bool? rearView,
    Map<String, double>? parts,
    bool? lightsOn,
    bool? hazards,
    Cable? cable,
    bool? powerFlow,
    Color? paint,
  }) {
    return HeroSceneState(
      rearView: rearView ?? this.rearView,
      parts: parts ?? this.parts,
      lightsOn: lightsOn ?? this.lightsOn,
      hazards: hazards ?? this.hazards,
      cable: cable ?? this.cable,
      powerFlow: powerFlow ?? this.powerFlow,
      paint: paint ?? this.paint,
    );
  }

  HeroSceneState withPart(String name, double value) =>
      copyWith(parts: {...parts, name: value});
}

/// What a renderer is given. Mirrors the hero interface in `docs/ui-hero.md`:
/// state and a box in, log lines out, nothing else.
class HeroRendererConfig {
  const HeroRendererConfig({
    required this.state,
    required this.model,
    required this.isDark,
    required this.log,
    this.compact = false,
    this.pauseWhenIdle = true,
    this.tuning = const {},
  });

  final HeroSceneState state;
  final SpikeModel model;
  final bool isDark;

  /// Small instance inside the grid: no event spam, skip optional work.
  final bool compact;

  /// Stop rendering once all animations have settled, if the renderer can.
  final bool pauseWhenIdle;

  /// Current values of the renderer's [TuningKnob]s, by name.
  final Map<String, double> tuning;

  double tune(String name, double fallback) => tuning[name] ?? fallback;

  /// Writes to the on-screen log and to logcat (tag `[spike]`).
  final void Function(String message) log;
}

/// Builds the renderer under test.
typedef HeroRendererBuilder =
    Widget Function(BuildContext context, HeroRendererConfig config);

/// A slider the renderer asks for, to tune values on the phone without a
/// rebuild (light intensities, emissive scale, ...).
class TuningKnob {
  const TuningKnob(this.name, this.min, this.max, this.initial);

  final String name;
  final double min;
  final double max;
  final double initial;
}
