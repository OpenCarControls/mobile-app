import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

/// The recent values of every series the paired vehicle's tiles draw, by
/// series id, for charts and sparklines.
///
/// Recorded from live state only, so a cached snapshot never shows up as a
/// point. Kept in memory: it starts empty with each app run and each vehicle.
class VehicleHistoryNotifier
    extends Notifier<Map<String, List<HistorySample>>> {
  final _buffers = <String, HistoryBuffer>{};

  /// The clock, replaceable in tests.
  DateTime Function() now = DateTime.now;

  @override
  Map<String, List<HistorySample>> build() {
    final vehicle = ref.watch(selectedVehicleProvider);
    // Two vehicles can share a platform and so a definition.
    ref.watch(pairedVehicleProvider.select((c) => c?.storageKey));
    _buffers.clear();
    if (vehicle == null) return const {};
    final series = vehicle.historySeries;
    if (series.isEmpty) return const {};
    ref.listen(vehicleStateProvider, (_, snapshot) {
      if (!snapshot.isStateLive) return;
      final time = now();
      var changed = false;
      for (final s in series) {
        final value = s.sample(snapshot);
        if (value == null || !value.isFinite) continue;
        _buffers.putIfAbsent(s.id, HistoryBuffer.new).add(time, value);
        changed = true;
      }
      if (changed) {
        state = {
          for (final MapEntry(:key, :value) in _buffers.entries)
            key: value.samples,
        };
      }
    });
    return const {};
  }
}

final vehicleHistoryProvider =
    NotifierProvider<VehicleHistoryNotifier, Map<String, List<HistorySample>>>(
      VehicleHistoryNotifier.new,
    );
