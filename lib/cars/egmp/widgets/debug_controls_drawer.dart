import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

class DebugControlsDrawer extends ConsumerWidget {
  const DebugControlsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stateNotifier = ref.read(vehicleStateProvider.notifier);
    final basicState = ref.watch(vehicleStateProvider).basicState as BasicState;
    
    Widget btn(String label, bool isOn, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.all(4.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isOn ? Colors.blue : Colors.grey.shade800,
            foregroundColor: Colors.white,
          ),
          onPressed: onTap,
          child: Text(label),
        ),
      );
    }

    return Drawer(
      backgroundColor: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Debug Controls',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
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
                    btn('Door FL', basicState.isDriverDoorOpen, () => stateNotifier.injectTestState(isDriverDoorOpen: !basicState.isDriverDoorOpen)),
                    btn('Door FR', basicState.isPassengerDoorOpen, () => stateNotifier.injectTestState(isPassengerDoorOpen: !basicState.isPassengerDoorOpen)),
                    btn('Door RL', basicState.isRearLeftDoorOpen, () => stateNotifier.injectTestState(isRearLeftDoorOpen: !basicState.isRearLeftDoorOpen)),
                    btn('Door RR', basicState.isRearRightDoorOpen, () => stateNotifier.injectTestState(isRearRightDoorOpen: !basicState.isRearRightDoorOpen)),
                    btn('Win FL', basicState.isDriverWindowOpen, () => stateNotifier.injectTestState(isDriverWindowOpen: !basicState.isDriverWindowOpen)),
                    btn('Win FR', basicState.isPassengerWindowOpen, () => stateNotifier.injectTestState(isPassengerWindowOpen: !basicState.isPassengerWindowOpen)),
                    btn('Win RL', basicState.isRearLeftWindowOpen, () => stateNotifier.injectTestState(isRearLeftWindowOpen: !basicState.isRearLeftWindowOpen)),
                    btn('Win RR', basicState.isRearRightWindowOpen, () => stateNotifier.injectTestState(isRearRightWindowOpen: !basicState.isRearRightWindowOpen)),
                    btn('Frunk', basicState.isFrunkOpen, () => stateNotifier.injectTestState(isFrunkOpen: !basicState.isFrunkOpen)),
                    btn('Trunk', basicState.isTrunkOpen, () => stateNotifier.injectTestState(isTrunkOpen: !basicState.isTrunkOpen)),
                    btn('Port', basicState.chargePortState != BasicState_ChargePortState.CHARGE_PORT_STATE_CLOSED && basicState.chargePortState != BasicState_ChargePortState.CHARGE_PORT_STATE_UNSPECIFIED, () {
                      final isOpen = basicState.chargePortState != BasicState_ChargePortState.CHARGE_PORT_STATE_CLOSED && basicState.chargePortState != BasicState_ChargePortState.CHARGE_PORT_STATE_UNSPECIFIED;
                      stateNotifier.injectTestState(chargePortState: isOpen ? BasicState_ChargePortState.CHARGE_PORT_STATE_CLOSED : BasicState_ChargePortState.CHARGE_PORT_STATE_OPEN);
                    }),
                    btn('Cable AC', basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CONNECTED || basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING, () {
                      final isConnected = basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CONNECTED || basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING;
                      stateNotifier.injectTestState(chargePortState: isConnected ? BasicState_ChargePortState.CHARGE_PORT_STATE_OPEN : BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CONNECTED);
                    }),
                    btn('Cable DC', basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CONNECTED || basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING || basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_NEGOTIATING, () {
                      final isConnected = basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CONNECTED || basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING || basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_NEGOTIATING;
                      stateNotifier.injectTestState(chargePortState: isConnected ? BasicState_ChargePortState.CHARGE_PORT_STATE_OPEN : BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CONNECTED);
                    }),
                    btn('Charging', basicState.powerFlowWatt != 0, () {
                      final isCharging = basicState.powerFlowWatt != 0;
                      final isAc = basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CONNECTED || basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING;
                      final isDc = basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CONNECTED || basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING || basicState.chargePortState == BasicState_ChargePortState.CHARGE_PORT_STATE_DC_NEGOTIATING;
                      
                      BasicState_ChargePortState newState = basicState.chargePortState;
                      if (!isCharging) {
                        if (isAc) newState = BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING;
                        else if (isDc) newState = BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING;
                        else newState = BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING;
                      } else {
                        if (isAc) newState = BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CONNECTED;
                        else if (isDc) newState = BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CONNECTED;
                        else newState = BasicState_ChargePortState.CHARGE_PORT_STATE_OPEN;
                      }
                      
                      stateNotifier.injectTestState(
                        powerFlowWatt: isCharging ? 0 : 50000,
                        chargePortState: newState,
                      );
                    }),
                    btn('Lights', basicState.areLightsOn, () => stateNotifier.injectTestState(areLightsOn: !basicState.areLightsOn)),
                    btn('Hazards', basicState.areHazardLightsOn, () => stateNotifier.injectTestState(areHazardLightsOn: !basicState.areHazardLightsOn)),
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
