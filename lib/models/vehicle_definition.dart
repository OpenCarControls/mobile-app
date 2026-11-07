import 'package:flutter/widgets.dart';
import 'package:protobuf/protobuf.dart';

import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/models/vehicle_history.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/car_transport.dart';

/// A vehicle platform: how to reach it, decode its state, and what the shared
/// dashboard shows for it. See "Vehicle description" in `docs/ui.md`.
abstract class VehicleDefinition {
  String get platformName;
  int get platformId;
  int get canBusCount;

  // ── Identity ────────────────────────────────────────────────────────────

  /// The vehicle's name until the user gives it one ("EV6").
  String get displayName;

  /// The platform in words, for settings and the vehicle list.
  String get platformLabel;

  /// The platform's accent colours and shapes.
  VehicleSkin get skin;

  /// The vehicle picture for [snapshot], filling the box it is given: behind
  /// the tiles on the remote tier, or in a Car view tile. It must not read
  /// providers or send commands (see `docs/ui-hero.md`).
  Widget buildHero(BuildContext context, VehicleSnapshot snapshot);

  /// The units the car displays.
  VehicleUnits units(VehicleSnapshot snapshot);

  // ── Energy and header ───────────────────────────────────────────────────

  /// The energy stores, one level row each in the header: a battery, a fuel
  /// tank, or both for a hybrid. Empty when the vehicle reports neither.
  List<EnergyDescription> get energy;

  /// The speed for the remote header while driving; null when not driving.
  int? drivingSpeedKmh(VehicleSnapshot snapshot);

  /// The remote header's status line ("Charging · 7.2 kW"), or null when it
  /// has nothing to say.
  String? statusLine(VehicleSnapshot snapshot);

  // ── Tiles ───────────────────────────────────────────────────────────────

  /// Every tile the platform offers.
  List<TileDefinition> get tiles;

  /// The tiles a new dashboard starts with on [tier], in order.
  List<TileLayoutEntry> defaultLayout(DashboardTier tier);

  /// The climate control, or null when the vehicle has none.
  ClimateDescription? get climate;

  String get mqttCommandTopicTemplate;
  String get mqttDataTopicTemplate;

  String get bleServiceUuid;
  String get bleAppToDeviceCharacteristicUuid;
  String get bleDeviceToAppCharacteristicUuid;

  /// Decode vehicle-specific basic state bytes into a typed proto instance.
  /// Called once per incoming message; result is stored and merged into state.
  GeneratedMessage decodeBasicState(List<int> bytes);

  /// Decode vehicle-specific advanced state bytes into a typed proto instance.
  /// Called once per incoming message; result is stored and merged into state.
  GeneratedMessage decodeAdvancedState(List<int> bytes);

  /// Build the vehicle's dashboard screen widget.
  Widget buildDashboard();

  /// Return a stub transport for this vehicle, or null if none is available.
  /// Used as a fallback when MQTT (and later BLE) are unavailable.
  CarTransport? createStubTransport();
}

/// Lookups over a vehicle's catalog.
extension VehicleCatalog on VehicleDefinition {
  /// The catalog tile with [id], or null.
  TileDefinition? tileById(String id) {
    for (final tile in tiles) {
      if (tile.id == id) return tile;
    }
    return null;
  }

  /// Every series the catalog's tiles draw, once each.
  List<HistorySeries> get historySeries {
    final byId = <String, HistorySeries>{};
    for (final tile in tiles) {
      for (final series in tile.series) {
        byId.putIfAbsent(series.id, () => series);
      }
    }
    return byId.values.toList();
  }
}
