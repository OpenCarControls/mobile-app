import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protobuf/protobuf.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

typedef _ChargePort = BasicState_ChargePortState;

const _kAcStates = {
  _ChargePort.CHARGE_PORT_STATE_AC_CONNECTED,
  _ChargePort.CHARGE_PORT_STATE_AC_CHARGING,
};

const _kDcStates = {
  _ChargePort.CHARGE_PORT_STATE_DC_NEGOTIATING,
  _ChargePort.CHARGE_PORT_STATE_DC_CONNECTED,
  _ChargePort.CHARGE_PORT_STATE_DC_CHARGING,
};

/// Debug-only drawer that edits the local basic state to exercise the UI and
/// the 3D animations without a device.
class DebugControlsDrawer extends ConsumerWidget {
  const DebugControlsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basicState = ref.watch(vehicleStateProvider).basicState as BasicState;
    final colors = Theme.of(context).colorScheme;

    void update(void Function(BasicState s) mutate) {
      final next = basicState.deepCopy();
      mutate(next);
      ref.read(vehicleStateProvider.notifier).debugOverrideBasicState(next);
    }

    final port = basicState.chargePortState;
    final isPortOpen =
        port != _ChargePort.CHARGE_PORT_STATE_CLOSED &&
        port != _ChargePort.CHARGE_PORT_STATE_UNSPECIFIED;
    final isAc = _kAcStates.contains(port);
    final isDc = _kDcStates.contains(port);
    final isCharging = basicState.powerFlowWatt != 0;

    _ChargePort toggledChargingPort() {
      if (isCharging) {
        if (isAc) return _ChargePort.CHARGE_PORT_STATE_AC_CONNECTED;
        if (isDc) return _ChargePort.CHARGE_PORT_STATE_DC_CONNECTED;
        return _ChargePort.CHARGE_PORT_STATE_OPEN;
      }
      if (isAc) return _ChargePort.CHARGE_PORT_STATE_AC_CHARGING;
      return _ChargePort.CHARGE_PORT_STATE_DC_CHARGING;
    }

    Widget btn(String label, bool isOn, void Function(BasicState s) mutate) {
      return Padding(
        padding: const EdgeInsets.all(4.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isOn
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            foregroundColor: isOn
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
          ),
          onPressed: () => update(mutate),
          child: Text(label),
        ),
      );
    }

    final b = basicState;
    return Drawer(
      backgroundColor: colors.surface,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    'Debug Controls',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: colors.onSurface),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8.0),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    btn(
                      'Door FL',
                      b.isDriverDoorOpen,
                      (s) => s.isDriverDoorOpen = !b.isDriverDoorOpen,
                    ),
                    btn(
                      'Door FR',
                      b.isPassengerDoorOpen,
                      (s) => s.isPassengerDoorOpen = !b.isPassengerDoorOpen,
                    ),
                    btn(
                      'Door RL',
                      b.isRearLeftDoorOpen,
                      (s) => s.isRearLeftDoorOpen = !b.isRearLeftDoorOpen,
                    ),
                    btn(
                      'Door RR',
                      b.isRearRightDoorOpen,
                      (s) => s.isRearRightDoorOpen = !b.isRearRightDoorOpen,
                    ),
                    btn(
                      'Win FL',
                      b.isDriverWindowOpen,
                      (s) => s.isDriverWindowOpen = !b.isDriverWindowOpen,
                    ),
                    btn(
                      'Win FR',
                      b.isPassengerWindowOpen,
                      (s) => s.isPassengerWindowOpen = !b.isPassengerWindowOpen,
                    ),
                    btn(
                      'Win RL',
                      b.isRearLeftWindowOpen,
                      (s) => s.isRearLeftWindowOpen = !b.isRearLeftWindowOpen,
                    ),
                    btn(
                      'Win RR',
                      b.isRearRightWindowOpen,
                      (s) => s.isRearRightWindowOpen = !b.isRearRightWindowOpen,
                    ),
                    btn(
                      'Frunk',
                      b.isFrunkOpen,
                      (s) => s.isFrunkOpen = !b.isFrunkOpen,
                    ),
                    btn(
                      'Trunk',
                      b.isTrunkOpen,
                      (s) => s.isTrunkOpen = !b.isTrunkOpen,
                    ),
                    btn(
                      'Port',
                      isPortOpen,
                      (s) => s.chargePortState = isPortOpen
                          ? _ChargePort.CHARGE_PORT_STATE_CLOSED
                          : _ChargePort.CHARGE_PORT_STATE_OPEN,
                    ),
                    btn(
                      'Cable AC',
                      isAc,
                      (s) => s.chargePortState = isAc
                          ? _ChargePort.CHARGE_PORT_STATE_OPEN
                          : _ChargePort.CHARGE_PORT_STATE_AC_CONNECTED,
                    ),
                    btn(
                      'Cable DC',
                      isDc,
                      (s) => s.chargePortState = isDc
                          ? _ChargePort.CHARGE_PORT_STATE_OPEN
                          : _ChargePort.CHARGE_PORT_STATE_DC_CONNECTED,
                    ),
                    btn('Charging', isCharging, (s) {
                      s.powerFlowWatt = isCharging ? 0 : 50000;
                      s.chargePortState = toggledChargingPort();
                    }),
                    btn(
                      'Lights',
                      b.areLightsOn,
                      (s) => s.areLightsOn = !b.areLightsOn,
                    ),
                    btn(
                      'Hazards',
                      b.areHazardLightsOn,
                      (s) => s.areHazardLightsOn = !b.areHazardLightsOn,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
