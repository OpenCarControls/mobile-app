import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

typedef _Port = BasicState_ChargePortState;
typedef _Seat = BasicState_SeatClimate;
typedef _Window = BasicState_WindowPosition;

VehicleSnapshot _live(BasicState basic, AdvancedState advanced) =>
    VehicleSnapshot(
      basicState: basic,
      advancedState: advanced,
      isStateLive: true,
      isAdvancedStateLive: true,
    );

BasicState _parked() => BasicState(
  odometer: 22916,
  isDriving: false,
  speed: 0,
  outdoorTemperature: 12,
  indoorTemperature: 19.5,
  isClimateOn: false,
  targetClimateTemperature: 21,
  isWindshieldDefrostOn: false,
  isRearWindowDefrostOn: false,
  isSteeringWheelHeaterOn: false,
  driverSeatClimate: _Seat.SEAT_CLIMATE_OFF,
  passengerSeatClimate: _Seat.SEAT_CLIMATE_OFF,
  batterySoc: 64,
  batteryRangeKm: 312,
  chargePortState: _Port.CHARGE_PORT_STATE_CLOSED,
  powerFlowWatt: 0,
  areDoorsLocked: true,
  isDriverDoorOpen: false,
  isPassengerDoorOpen: false,
  isRearLeftDoorOpen: false,
  isRearRightDoorOpen: false,
  driverWindowPosition: _Window.WINDOW_POSITION_CLOSED,
  passengerWindowPosition: _Window.WINDOW_POSITION_CLOSED,
  rearLeftWindowPosition: _Window.WINDOW_POSITION_CLOSED,
  rearRightWindowPosition: _Window.WINDOW_POSITION_CLOSED,
  isFrunkOpen: false,
  isTrunkOpen: false,
  acChargeLimitPercent: 80,
  dcChargeLimitPercent: 90,
  temperatureUnit: BasicState_TemperatureUnit.TEMPERATURE_UNIT_CELSIUS,
  distanceUnit: BasicState_DistanceUnit.DISTANCE_UNIT_KILOMETERS,
);

AdvancedState _off() => AdvancedState(
  batteryVoltage: 697,
  instantaneousPowerWatt: 0,
  batteryMinimumTemperature: 24,
  batteryMaximumTemperature: 27,
  preconditioningState:
      AdvancedState_PreconditioningState.PRECONDITIONING_STATE_OFF,
  gear: AdvancedState_Gear.GEAR_PARK,
  powerState: AdvancedState_PowerState.POWER_STATE_OFF,
);

/// Made-up states for the debug gallery, one per look of the tiles.
List<({String name, VehicleSnapshot snapshot})> egmpSamples() => [
  (name: 'Parked', snapshot: _live(_parked(), _off())),
  (
    name: 'Charging, climate on',
    snapshot: _live(
      _parked()
        ..chargePortState = _Port.CHARGE_PORT_STATE_AC_CHARGING
        ..powerFlowWatt = 7200
        ..timeRemainingMinutes = 65
        ..isClimateOn = true
        ..isWindshieldDefrostOn = true
        ..driverSeatClimate = _Seat.SEAT_CLIMATE_HEAT_LEVEL_2,
      _off()..instantaneousPowerWatt = 7200,
    ),
  ),
  (
    name: 'Driving',
    snapshot: _live(
      _parked()
        ..isDriving = true
        ..speed = 88
        ..areDoorsLocked = false
        ..rearLeftWindowPosition = _Window.WINDOW_POSITION_PARTLY_OPEN,
      _off()
        ..instantaneousPowerWatt = -35000
        ..gear = AdvancedState_Gear.GEAR_DRIVE
        ..powerState = AdvancedState_PowerState.POWER_STATE_READY
        ..preconditioningState =
            AdvancedState_PreconditioningState.PRECONDITIONING_STATE_HEATING,
    ),
  ),
  (
    name: 'V2L, miles and °F',
    snapshot: _live(
      _parked()
        ..chargePortState = _Port.CHARGE_PORT_STATE_V2L_ACTIVE
        ..powerFlowWatt = -1800
        ..isTrunkOpen = true
        ..isDriverDoorOpen = true
        ..isClimateOn = true
        ..passengerSeatClimate = _Seat.SEAT_CLIMATE_HEAT_LEVEL_3
        ..temperatureUnit =
            BasicState_TemperatureUnit.TEMPERATURE_UNIT_FAHRENHEIT
        ..distanceUnit = BasicState_DistanceUnit.DISTANCE_UNIT_MILES,
      _off()..instantaneousPowerWatt = -1800,
    ),
  ),
  (
    name: 'Nothing reported',
    snapshot: VehicleSnapshot(
      basicState: BasicState(),
      advancedState: AdvancedState(),
    ),
  ),
];
