import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/models/vehicle_summary.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/providers/vehicle_list_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/screens/dashboard/dashboard_header.dart'
    show connectionLabel, formatUpdatedAgo;
import 'package:open_car_app/screens/dashboard/dashboard_screen.dart'
    show dashboardTierFor;
import 'package:open_car_app/theme/vehicle_skin.dart';

/// A vehicle's circular avatar, in its own skin's colours so that the cars in
/// a list are easy to tell apart.
class VehicleAvatar extends StatelessWidget {
  const VehicleAvatar({super.key, required this.skin, this.size = 44});

  final VehicleSkin skin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accents = skin.accentsFor(Theme.of(context).brightness);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accents.accentContainer,
        ),
        child: Icon(
          Symbols.directions_car,
          size: size * 0.55,
          color: accents.onAccentContainer,
        ),
      ),
    );
  }
}

/// The line under a vehicle's name in the lists: its last known level and
/// range, then its state. The current vehicle's state is its connection,
/// as the connection pill shows it; another's is when it was last updated.
/// For example "64% · 312 km · Remote" or "41% · 380 km · Updated 3 h ago".
String vehicleStatusLine(VehicleSummary? summary, {required String state}) {
  final unit = summary?.distanceUnit ?? DistanceUnit.kilometers;
  return [
    if (summary?.levelPercent case final level?) '$level%',
    if (summary?.rangeKm case final range?) formatRange(range, unit),
    state,
  ].join(' · ');
}

/// The state of a vehicle that isn't current.
String idleVehicleState(VehicleSummary? summary, DateTime now) =>
    switch (summary?.lastUpdated) {
      final updated? => 'Updated ${formatUpdatedAgo(updated, now)}',
      null => 'Not updated yet',
    };

/// [vehicleStatusLine] for [entry], following the live connection when it
/// is the current vehicle.
String vehicleStatusText(WidgetRef ref, VehicleListEntry entry) {
  final now = DateTime.now();
  final state = entry.current
      ? connectionLabel(
          ref.watch(vehicleStateProvider),
          dashboardTierFor(ref.watch(transportTypeProvider)),
          now,
        )
      : idleVehicleState(entry.summary, now);
  return vehicleStatusLine(entry.summary, state: state);
}
