import 'package:flutter/foundation.dart';

import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

/// Which charging cable the model shows plugged in.
enum EgmpCable { none, l2, dc }

/// States drawn with the small L2 cable. `CONNECTED` (cable in, charger type
/// not known yet) uses it too until the model gets a generic cable.
const _kL2CableStates = {
  BasicState_ChargePortState.CHARGE_PORT_STATE_CONNECTED,
  BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CONNECTED,
  BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING,
};

const _kDcCableStates = {
  BasicState_ChargePortState.CHARGE_PORT_STATE_DC_NEGOTIATING,
  BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CONNECTED,
  BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING,
};

/// How far along its open animation a window is shown, from 0 (closed) to 1
/// (fully open). The car reports steps, not a position: in log_07 "slightly"
/// lasts about the first 30% of the travel and "partly" the rest until the
/// bottom, so each step is shown inside its range.
double _windowOpenFraction(BasicState_WindowPosition position) {
  return switch (position) {
    BasicState_WindowPosition.WINDOW_POSITION_SLIGHTLY_OPEN => 0.2,
    BasicState_WindowPosition.WINDOW_POSITION_PARTLY_OPEN => 0.6,
    BasicState_WindowPosition.WINDOW_POSITION_FULLY_OPEN => 1.0,
    _ => 0.0,
  };
}

/// What the E-GMP hero shows for a snapshot: the targets the renderer
/// animates towards. It holds no animation state.
@immutable
class EgmpScene {
  const EgmpScene({
    this.rearView = false,
    this.parts = const {},
    this.lightsOn = false,
    this.hazards = false,
    this.cable = EgmpCable.none,
    this.powerFlow = false,
  });

  factory EgmpScene.fromSnapshot(VehicleSnapshot snapshot) {
    final s = snapshot.basicState as BasicState;
    final port = s.chargePortState;
    final portOpen =
        port != BasicState_ChargePortState.CHARGE_PORT_STATE_CLOSED &&
        port != BasicState_ChargePortState.CHARGE_PORT_STATE_UNSPECIFIED;
    final cable = _kL2CableStates.contains(port)
        ? EgmpCable.l2
        : _kDcCableStates.contains(port)
        ? EgmpCable.dc
        : EgmpCable.none;
    double flag(bool open) => open ? 1 : 0;
    return EgmpScene(
      // The EV6's charge port is at the rear passenger side.
      rearView: portOpen,
      parts: {
        'Anim_ChargePort': flag(portOpen),
        'Anim_Connect_L2': flag(cable == EgmpCable.l2),
        'Anim_Connect_DC': flag(cable == EgmpCable.dc),
        'Anim_Door_FL': flag(s.isDriverDoorOpen),
        'Anim_Door_FR': flag(s.isPassengerDoorOpen),
        'Anim_Door_RL': flag(s.isRearLeftDoorOpen),
        'Anim_Door_RR': flag(s.isRearRightDoorOpen),
        'Anim_Hood': flag(s.isFrunkOpen),
        'Anim_Trunk': flag(s.isTrunkOpen),
        'Anim_Window_FL': _windowOpenFraction(s.driverWindowPosition),
        'Anim_Window_FR': _windowOpenFraction(s.passengerWindowPosition),
        'Anim_Window_RL': _windowOpenFraction(s.rearLeftWindowPosition),
        'Anim_Window_RR': _windowOpenFraction(s.rearRightWindowPosition),
      },
      lightsOn: s.areLightsOn,
      hazards: s.areHazardLightsOn,
      cable: cable,
      powerFlow: s.powerFlowWatt != 0,
    );
  }

  /// Camera at the rear passenger side instead of the front driver side.
  final bool rearView;

  /// Target position of each glTF animation, from 0 (closed) to 1 (open).
  /// Missing entries are 0.
  final Map<String, double> parts;

  final bool lightsOn;
  final bool hazards;
  final EgmpCable cable;

  /// The charging glow: an emissive fade and a scrolling texture on the
  /// cable.
  final bool powerFlow;

  double part(String name) => parts[name] ?? 0;

  @override
  bool operator ==(Object other) =>
      other is EgmpScene &&
      other.rearView == rearView &&
      mapEquals(other.parts, parts) &&
      other.lightsOn == lightsOn &&
      other.hazards == hazards &&
      other.cable == cable &&
      other.powerFlow == powerFlow;

  @override
  int get hashCode => Object.hash(
    rearView,
    Object.hashAllUnordered(parts.entries.map((e) => (e.key, e.value))),
    lightsOn,
    hazards,
    cable,
    powerFlow,
  );
}

/// A light material's look: base colour (null keeps the model's), emissive
/// colour, and an intensity on the Three.js scale the values were first
/// tuned with (the renderer converts it).
typedef EgmpLook = ({int? color, int emissive, double intensity});

/// The light materials the hero drives, by glTF material name.
const kEgmpLightMaterials = {
  'Headlights',
  'TopDRLs',
  'BottomDRLs',
  'BrakeLight_Bar_Main',
  'BrakeLight_Side_Main',
  'BrakeLight_Side_Base1',
  'MirrorTurnSignals',
};

/// The looks of [kEgmpLightMaterials] for [scene], with the hazards in the
/// on half of their blink when [blinkOn].
Map<String, EgmpLook> egmpLooks(EgmpScene scene, {required bool blinkOn}) {
  final lights = scene.lightsOn ? 0xffffff : 0x000000;
  final lightsIntensity = scene.lightsOn ? 50.0 : 0.0;
  // The brake lights follow the lights until the state reports braking.
  final brake = scene.lightsOn ? 20.0 : 0.0;
  final hazardOn = scene.hazards && blinkOn;
  const amber = (color: 0xffc400, emissive: 0xffc400, intensity: 50.0);
  return {
    'Headlights': (color: null, emissive: lights, intensity: lightsIntensity),
    'BottomDRLs': (color: null, emissive: lights, intensity: lightsIntensity),
    'BrakeLight_Bar_Main': (color: null, emissive: 0xff0000, intensity: brake),
    'BrakeLight_Side_Main': (color: null, emissive: 0xff0000, intensity: brake),
    'TopDRLs': hazardOn
        ? amber
        : (color: 0xffffff, emissive: lights, intensity: lightsIntensity),
    'MirrorTurnSignals': hazardOn
        ? amber
        : (color: 0xe7e7e7, emissive: 0x000000, intensity: 0.0),
    'BrakeLight_Side_Base1': (
      color: null,
      emissive: 0x970000,
      intensity: hazardOn ? 20.0 : 0.0,
    ),
  };
}
