import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_car_app/formatting/units.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_definition.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/tiles/catalog_tile.dart';
import 'package:open_car_app/widgets/tiles/tile_context.dart';
import 'package:open_car_app/widgets/tiles/tile_grid.dart';

/// How long a fake command takes to answer.
const _fakeCommandDelay = Duration(milliseconds: 1200);

/// Each vehicle's default layouts, drawn from its sample states with the real
/// tile widgets. Commands are fake: they only wait, and the state doesn't
/// change; pick another sample to see another state.
class VehicleLayoutsGallerySection extends ConsumerWidget {
  const VehicleLayoutsGallerySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProviderScope(
      overrides: [
        commandUiStateProvider.overrideWith(
          (ref, key) => CommandUiState.enabled,
        ),
        tileCommandSenderProvider.overrideWithValue((key, message) async {
          await Future<void>.delayed(_fakeCommandDelay);
          return null;
        }),
      ],
      child: VehicleLayoutsGallery(
        vehicles: ref.watch(availableVehiclesProvider),
      ),
    );
  }
}

/// The pickers and the grid of [VehicleLayoutsGallerySection].
class VehicleLayoutsGallery extends StatefulWidget {
  const VehicleLayoutsGallery({super.key, required this.vehicles});

  final List<VehicleDefinition> vehicles;

  @override
  State<VehicleLayoutsGallery> createState() => _VehicleLayoutsGalleryState();
}

class _VehicleLayoutsGalleryState extends State<VehicleLayoutsGallery> {
  int _vehicle = 0;
  int _sample = 0;
  DashboardTier _tier = DashboardTier.bluetooth;
  bool _iconOnly = false;
  int _columns = kTileColumnsPhone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final vehicle = widget.vehicles[_vehicle];
    final samples = vehicle.sampleSnapshots;
    final sample = samples[math.min(_sample, samples.length - 1)];
    final snapshot = sample.snapshot;
    final data = TileContext(
      vehicle: vehicle,
      snapshot: snapshot,
      history: sampleHistory(vehicle, snapshot),
      iconOnly: _iconOnly,
    );
    final items = catalogGridItems(
      vehicle.defaultLayout(_tier),
      data,
      tiers: _tier == DashboardTier.remote
          ? const {TileTier.basic}
          : const {TileTier.basic, TileTier.advanced},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        DropdownButton<int>(
          isExpanded: true,
          value: _vehicle,
          items: [
            for (final (index, v) in widget.vehicles.indexed)
              DropdownMenuItem(
                value: index,
                child: Text('${v.displayName} (${v.platformLabel})'),
              ),
          ],
          onChanged: (index) => setState(() {
            _vehicle = index!;
            _sample = 0;
          }),
        ),
        DropdownButton<int>(
          isExpanded: true,
          value: math.min(_sample, samples.length - 1),
          items: [
            for (final (index, s) in samples.indexed)
              DropdownMenuItem(value: index, child: Text(s.name)),
          ],
          onChanged: (index) => setState(() => _sample = index!),
        ),
        SegmentedButton<DashboardTier>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: DashboardTier.remote, label: Text('Remote')),
            ButtonSegment(
              value: DashboardTier.bluetooth,
              label: Text('Bluetooth'),
            ),
          ],
          selected: {_tier},
          onSelectionChanged: (picked) => setState(() => _tier = picked.single),
        ),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: kTileColumnsPhone, label: Text('4 columns')),
            ButtonSegment(value: kTileColumnsWide, label: Text('8 columns')),
          ],
          selected: {_columns},
          onSelectionChanged: (picked) =>
              setState(() => _columns = picked.single),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Icon-only buttons'),
          value: _iconOnly,
          onChanged: (value) => setState(() => _iconOnly = value),
        ),
        _HeaderPreview(vehicle: vehicle, snapshot: snapshot),
        TileGrid(columns: _columns, items: items),
        Text(
          'Not in this layout: ${_unused(vehicle).join(', ')}',
          style: AppTextStyles.caption.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }

  List<String> _unused(VehicleDefinition vehicle) {
    final used = {for (final e in vehicle.defaultLayout(_tier)) e.tileId};
    return [
      for (final tile in vehicle.tiles)
        if (!used.contains(tile.id) &&
            (_tier == DashboardTier.bluetooth || tile.tier == TileTier.basic))
          tile.id,
    ];
  }
}

/// What the header would show: the level rows, the speed and the status line.
class _HeaderPreview extends StatelessWidget {
  const _HeaderPreview({required this.vehicle, required this.snapshot});

  final VehicleDefinition vehicle;
  final VehicleSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final units = vehicle.units(snapshot);
    final speed = vehicle.drivingSpeedKmh(snapshot);
    final status = vehicle.statusLine(snapshot);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(vehicle.displayName, style: AppTextStyles.vehicleName),
        for (final energy in vehicle.energy)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: 8,
            children: [
              Text(switch (energy.levelPercent(snapshot)) {
                final level? => '$level%',
                null => '—',
              }, style: AppTextStyles.level),
              if (energy.rangeKm(snapshot) case final range?)
                Text(
                  formatRange(range, units.distance),
                  style: AppTextStyles.range.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              const Spacer(),
              if (speed != null)
                Text(
                  formatSpeed(speed, units.distance),
                  style: AppTextStyles.range,
                ),
            ],
          ),
        if (status != null)
          Text(status, style: TextStyle(color: tokens.accent)),
      ],
    );
  }
}

/// A made-up history for every series of [vehicle]: 30 minutes that wander
/// around the series' value in [snapshot] and end on it.
Map<String, List<HistorySample>> sampleHistory(
  VehicleDefinition vehicle,
  VehicleSnapshot snapshot,
) {
  const points = 30;
  final end = DateTime(2026);
  return {
    for (final series in vehicle.historySeries)
      if (series.sample(snapshot) case final value?)
        series.id: [
          for (var i = 0; i < points; i++)
            (
              time: end.subtract(Duration(minutes: points - 1 - i)),
              value: i == points - 1
                  ? value
                  : value +
                        (value.abs() * 0.05 + 0.5) *
                            math.sin(i * 0.5 + series.id.length) *
                            (points - i) /
                            points,
            ),
        ],
  };
}
