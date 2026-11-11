import 'package:open_car_app/cars/egmp/state_access.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/models/tile_catalog.dart';
import 'package:open_car_app/models/vehicle_description.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

typedef _Port = BasicState_ChargePortState;

const _charging = {
  _Port.CHARGE_PORT_STATE_AC_CHARGING,
  _Port.CHARGE_PORT_STATE_DC_CHARGING,
};

/// Whether the battery is charging or exporting, and how fast. Also feeds the
/// header status line.
EnergyStatus egmpEnergyStatus(VehicleSnapshot s) {
  final b = egmpBasic(s);
  final power = b.hasPowerFlowWatt() && b.powerFlowWatt != 0
      ? b.powerFlowWatt.abs()
      : null;
  final dc = b.chargePortState == _Port.CHARGE_PORT_STATE_DC_CHARGING;
  // Like the cluster: the time to the limit that applies, and on DC to 80%.
  final limit = dc
      ? (b.hasDcChargeLimitPercent() ? b.dcChargeLimitPercent : null)
      : (b.hasAcChargeLimitPercent() ? b.acChargeLimitPercent : null);
  if (_charging.contains(b.chargePortState)) {
    return EnergyStatus(
      flow: EnergyFlow.charging,
      powerWatts: power,
      limitPercent: limit,
      timeToLimitMinutes: b.hasTimeRemainingMinutes()
          ? b.timeRemainingMinutes
          : null,
      timeTo80PercentMinutes: dc && b.hasTimeTo80PercentMinutes()
          ? b.timeTo80PercentMinutes
          : null,
    );
  }
  if (b.chargePortState == _Port.CHARGE_PORT_STATE_V2L_ACTIVE) {
    return EnergyStatus(flow: EnergyFlow.exporting, powerWatts: power);
  }
  return EnergyStatus(limitPercent: limit);
}

final egmpBattery = EnergyDescription(
  kind: EnergyKind.battery,
  levelPercent: (s) =>
      egmpBasic(s).hasBatterySoc() ? egmpBasic(s).batterySoc : null,
  rangeKm: (s) =>
      egmpBasic(s).hasBatteryRangeKm() ? egmpBasic(s).batteryRangeKm : null,
  status: egmpEnergyStatus,
);

final egmpBatteryTile = EnergyTileDefinition(
  id: 'battery',
  label: 'Battery',
  tier: TileTier.basic,
  energy: egmpBattery,
);
