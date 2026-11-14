import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// On-screen event log, mirrored to logcat with a `[spike]` prefix so a
/// session can be read back with `adb logcat -s flutter`.
class SpikeLog extends ChangeNotifier {
  SpikeLog() : _start = DateTime.now();

  final DateTime _start;
  final _lines = ListQueue<String>();

  List<String> get lines => List.unmodifiable(_lines);

  void add(String message) {
    final t = DateTime.now().difference(_start).inMilliseconds / 1000;
    final line = '${t.toStringAsFixed(2).padLeft(7)}s  $message';
    debugPrint('[spike] $line');
    _lines.addFirst(line);
    while (_lines.length > 40) {
      _lines.removeLast();
    }
    notifyListeners();
  }
}

/// A rolling summary of Flutter frame timings and process memory.
///
/// Frame numbers only cover frames Flutter produced: an idle screen produces
/// none, so "0 fps" while nothing moves is good, not bad. Memory is the
/// process RSS; GPU memory held by the driver may not show there (use
/// `adb shell dumpsys meminfo <package>` for the Graphics line).
class SpikeMetrics extends ChangeNotifier with WidgetsBindingObserver {
  SpikeMetrics(this.log) {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    WidgetsBinding.instance.addObserver(this);
    _memoryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sampleMemory();
      _trimFrames();
      notifyListeners();
    });
    _sampleMemory();
  }

  final SpikeLog log;
  late final Timer _memoryTimer;
  final _frames = ListQueue<({DateTime at, double buildMs, double rasterMs})>();

  static const _window = Duration(seconds: 2);
  static const _budgetMs = 1000 / 60;

  int rssMb = 0;
  int peakRssMb = 0;

  /// Frames over budget since the last [resetJank].
  int jankFrames = 0;
  int totalFrames = 0;

  double get fps => _frames.length / _window.inSeconds;

  double get worstBuildMs =>
      _frames.fold(0.0, (m, f) => f.buildMs > m ? f.buildMs : m);
  double get worstRasterMs =>
      _frames.fold(0.0, (m, f) => f.rasterMs > m ? f.rasterMs : m);
  double get avgRasterMs => _frames.isEmpty
      ? 0
      : _frames.fold(0.0, (s, f) => s + f.rasterMs) / _frames.length;

  void resetJank() {
    jankFrames = 0;
    totalFrames = 0;
    peakRssMb = rssMb;
    log.add('counters reset');
    notifyListeners();
  }

  /// A one-line summary for the log, e.g. at the end of a scripted run.
  String summary() =>
      'fps ${fps.toStringAsFixed(0)}, raster avg ${avgRasterMs.toStringAsFixed(1)} '
      'worst ${worstRasterMs.toStringAsFixed(1)} ms, build worst '
      '${worstBuildMs.toStringAsFixed(1)} ms, jank $jankFrames/$totalFrames, '
      'rss $rssMb MB (peak $peakRssMb)';

  void _onTimings(List<FrameTiming> timings) {
    final now = DateTime.now();
    for (final t in timings) {
      final buildMs = t.buildDuration.inMicroseconds / 1000;
      final rasterMs = t.rasterDuration.inMicroseconds / 1000;
      _frames.add((at: now, buildMs: buildMs, rasterMs: rasterMs));
      totalFrames++;
      if (buildMs > _budgetMs || rasterMs > _budgetMs) jankFrames++;
    }
    _trimFrames();
  }

  void _trimFrames() {
    final cutoff = DateTime.now().subtract(_window);
    while (_frames.isNotEmpty && _frames.first.at.isBefore(cutoff)) {
      _frames.removeFirst();
    }
  }

  void _sampleMemory() {
    rssMb = ProcessInfo.currentRss ~/ (1024 * 1024);
    if (rssMb > peakRssMb) peakRssMb = rssMb;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log.add('lifecycle: ${state.name}  (${summary()})');
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    WidgetsBinding.instance.removeObserver(this);
    _memoryTimer.cancel();
    super.dispose();
  }
}
