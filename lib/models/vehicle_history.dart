import 'package:flutter/foundation.dart';

import 'package:open_car_app/providers/vehicle_state_provider.dart';

/// A numeric value that charts and sparklines draw over time, read from the
/// vehicle state. The history keeps one series per [id] for the paired vehicle.
@immutable
class HistorySeries {
  const HistorySeries({required this.id, required this.sample});

  /// Stable and unique within a vehicle's catalog.
  final String id;

  /// The value now, or null when the state doesn't have it (not reported, or
  /// advanced state that isn't live).
  final double? Function(VehicleSnapshot snapshot) sample;
}

/// One recorded value of a [HistorySeries].
typedef HistorySample = ({DateTime time, double value});

/// The recent values of one series: at most one sample per [interval], none
/// older than [window].
class HistoryBuffer {
  HistoryBuffer({
    this.interval = const Duration(seconds: 5),
    this.window = const Duration(minutes: 30),
  });

  final Duration interval;
  final Duration window;
  final _samples = <HistorySample>[];

  List<HistorySample> get samples => List.unmodifiable(_samples);

  /// Records [value] at [time], unless the last sample is more recent than
  /// [interval]; then the last sample takes the newer value, so the end of a
  /// chart is always current.
  void add(DateTime time, double value) {
    final last = _samples.lastOrNull;
    if (last != null && time.difference(last.time) < interval) {
      _samples.last = (time: last.time, value: value);
    } else {
      _samples.add((time: time, value: value));
    }
    final oldest = time.subtract(window);
    _samples.removeWhere((s) => s.time.isBefore(oldest));
  }
}
