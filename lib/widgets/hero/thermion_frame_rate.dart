import 'dart:math' as math;

import 'package:thermion_flutter/thermion_flutter.dart' show FilamentApp;

/// Rate of Thermion's render loop while every hero is idle (rendering
/// paused). Its scheduler keeps ticking even then, so it is slowed down.
const kThermionIdleFps = 10;

/// The app's heroes share this one.
final thermionFrameRate = ThermionFrameRate(
  (fps) => FilamentApp.instance?.setTargetFramerate(fps),
);

/// Thermion has one render-loop rate for the whole engine, but each hero
/// (the remote-tier box, a Car view tile) wants its own. Each one requests a
/// rate and the engine runs at the highest request.
class ThermionFrameRate {
  ThermionFrameRate(this._apply);

  /// Sets the engine's rate (`FilamentApp.setTargetFramerate`).
  final void Function(int fps) _apply;

  final _requests = <Object, int>{};
  int? _applied;

  /// The rate the engine was last set to.
  int? get applied => _applied;

  void request(Object owner, int fps) {
    _requests[owner] = fps;
    _update();
  }

  void release(Object owner) {
    _requests.remove(owner);
    _update();
  }

  void _update() {
    final fps = _requests.values.fold(kThermionIdleFps, math.max);
    if (fps == _applied) return;
    _applied = fps;
    _apply(fps);
  }
}
