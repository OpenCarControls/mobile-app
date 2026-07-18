import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import '../widgets/vehicle_3d_viewer.dart';

class EgmpDashboardScreen extends ConsumerStatefulWidget {
  const EgmpDashboardScreen({super.key});

  @override
  ConsumerState<EgmpDashboardScreen> createState() =>
      _EgmpDashboardScreenState();
}

class _EgmpDashboardScreenState extends ConsumerState<EgmpDashboardScreen> {
  String? _currentSubMenu;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('E-GMP Platform'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Switch Vehicle',
            onPressed: () {
              // Placeholder for switching vehicle
            },
          ),
        ],
      ),
      body: isWideScreen ? _buildWideLayout() : _buildNarrowLayout(),
    );
  }

  Widget _buildNarrowLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: 400, child: _buildVehicleRepresentation()),
          _buildDebugControls(),
          _buildRightPanel(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
          ),
        ],
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(child: _buildVehicleRepresentation()),
              _buildDebugControls(),
            ],
          ),
        ),
        SizedBox(width: 350, child: _buildRightPanel()),
      ],
    );
  }

  Widget _buildDebugControls() {
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

    return Container(
      padding: const EdgeInsets.all(8.0),
      color: Colors.black26,
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
          btn('Lights', basicState.areLightsOn, () => stateNotifier.injectTestState(areLightsOn: !basicState.areLightsOn)),
          btn('Hazards', basicState.areHazardLightsOn, () => stateNotifier.injectTestState(areHazardLightsOn: !basicState.areHazardLightsOn)),
        ],
      ),
    );
  }

  Widget _buildVehicleRepresentation() {
    final state = ref.watch(vehicleStateProvider);
    final basicState = state.basicState as BasicState;

    final batterySoc = basicState.batterySoc;
    final batteryRange = basicState.batteryRangeKm;
    final powerFlow = basicState.powerFlowWatt;
    final odometer = basicState.odometer;
    final isDriving = basicState.isDriving;
    final speed = basicState.speed;
    final chargePortState = basicState.chargePortState;
    final timeRemaining = basicState.timeRemainingMinutes;

    final isLocked = basicState.areDoorsLocked;
    final isChargePortOpen =
        basicState.chargePortState ==
        BasicState_ChargePortState.CHARGE_PORT_STATE_OPEN;
    final areLightsOn = basicState.areLightsOn;
    final isClimateOn = basicState.isClimateOn;

    final bool isCharging =
        chargePortState ==
            BasicState_ChargePortState.CHARGE_PORT_STATE_AC_CHARGING ||
        chargePortState ==
            BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING;
    final bool isV2L =
        chargePortState ==
        BasicState_ChargePortState.CHARGE_PORT_STATE_V2L_ACTIVE;

    final String powerFlowStr = (powerFlow != 0 && (isCharging || isV2L))
        ? ' ${(powerFlow > 0 ? '+' : '')}${(powerFlow / 1000).toStringAsFixed(1)} kW'
        : '';

    final String chargeStatusStr = isCharging
        ? 'Charging • $timeRemaining mins to full'
        : (isV2L ? 'V2L Active' : '');

    return Container(
      color: Colors.grey.shade900,
      child: Stack(
        children: [
          Positioned.fill(child: const Vehicle3DViewer()),
          Positioned(
            top: 24,
            left: 24,
            right: 24,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$batteryRange km - $batterySoc% 🔋$powerFlowStr',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (chargeStatusStr.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          chargeStatusStr,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                  ],
                ),
                Text(
                  '$odometer km',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (isDriving)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '$speed km/h',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            ),
          if (_currentSubMenu == 'climate')
            const Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Text(
                'Vehicle Representation\n(Top-down interior view placeholder)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          if (_currentSubMenu == null)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildQuickActionButton(
                    icon: isLocked ? Icons.lock : Icons.lock_open,
                    isActive: isLocked,
                    onPressed: () {
                      final cmd = BasicCommand(
                        doorLockCommand: DoorLockCommand(lock: !isLocked),
                      );
                      ref
                          .read(vehicleStateProvider.notifier)
                          .sendBasicCommand(cmd.writeToBuffer());
                    },
                  ),
                  const SizedBox(width: 16),
                  _buildQuickActionButton(
                    icon: isChargePortOpen
                        ? Icons.ev_station
                        : Icons.ev_station_outlined,
                    isActive: isChargePortOpen,
                    onPressed: () {
                      final cmd = BasicCommand(
                        chargePortCommand: ChargePortCommand(
                          open: !isChargePortOpen,
                        ),
                      );
                      ref
                          .read(vehicleStateProvider.notifier)
                          .sendBasicCommand(cmd.writeToBuffer());
                    },
                  ),
                  const SizedBox(width: 16),
                  _buildQuickActionButton(
                    icon: Icons.highlight,
                    isActive: areLightsOn,
                    onPressed: () {
                      final cmd = BasicCommand(
                        flashLightsCommand: FlashLightsCommand(),
                      );
                      ref
                          .read(vehicleStateProvider.notifier)
                          .sendBasicCommand(cmd.writeToBuffer());
                    },
                  ),
                  const SizedBox(width: 16),
                  _buildQuickActionButton(
                    icon: Icons.ac_unit,
                    isActive: isClimateOn,
                    onPressed: () {
                      final cmd = BasicCommand(
                        climateControlCommand: ClimateControlCommand(
                          climateOn: !isClimateOn,
                        ),
                      );
                      ref
                          .read(vehicleStateProvider.notifier)
                          .sendBasicCommand(cmd.writeToBuffer());
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.shade700 : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 32),
      ),
    );
  }

  Widget _buildRightPanel({bool shrinkWrap = false, ScrollPhysics? physics}) {
    if (_currentSubMenu == 'climate') {
      return _buildClimateMenu(shrinkWrap: shrinkWrap, physics: physics);
    } else if (_currentSubMenu == 'settings') {
      return _buildSettingsMenu(shrinkWrap: shrinkWrap, physics: physics);
    } else {
      return _buildMainMenu(shrinkWrap: shrinkWrap, physics: physics);
    }
  }

  Widget _buildMainMenu({bool shrinkWrap = false, ScrollPhysics? physics}) {
    final state = ref.watch(vehicleStateProvider);
    final basicState = state.basicState as BasicState;
    return Container(
      color: Colors.black87,
      child: ListView(
        shrinkWrap: shrinkWrap,
        physics: physics,
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        children: [
          _buildMenuTile(
            icon: Icons.ac_unit,
            title: 'Climate & Windows',
            subtitle:
                'Indoor: ${basicState.indoorTemperature.toStringAsFixed(1)}°C',
            onTap: () => setState(() => _currentSubMenu = 'climate'),
          ),
          _buildMenuTile(
            icon: Icons.settings,
            title: 'Settings',
            onTap: () => setState(() => _currentSubMenu = 'settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildClimateMenu({bool shrinkWrap = false, ScrollPhysics? physics}) {
    final state = ref.watch(vehicleStateProvider);
    final basicState = state.basicState as BasicState;

    final isClimateOn = basicState.isClimateOn;
    final targetTemp = basicState.targetClimateTemperature == 0
        ? 22.0
        : basicState.targetClimateTemperature;
    final isWindshieldDefrostOn = basicState.isWindshieldDefrostOn;
    final isRearDefrostOn = basicState.isRearWindowDefrostOn;
    final isSteeringHeaterOn = basicState.isSteeringWheelHeaterOn;
    final outdoorTemp = basicState.outdoorTemperature;
    final indoorTemp = basicState.indoorTemperature;

    return Container(
      color: Colors.black87,
      child: ListView(
        shrinkWrap: shrinkWrap,
        physics: physics,
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => setState(() => _currentSubMenu = null),
            ),
            title: const Text(
              'Climate & Windows',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Outdoor: ${outdoorTemp.toStringAsFixed(1)}°C',
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  'Indoor: ${indoorTemp.toStringAsFixed(1)}°C',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildClimateIconButton(
                icon: Icons.power_settings_new,
                isActive: isClimateOn,
                onTap: () {
                  final cmd = BasicCommand(
                    climateControlCommand: ClimateControlCommand(
                      climateOn: !isClimateOn,
                    ),
                  );
                  ref
                      .read(vehicleStateProvider.notifier)
                      .sendBasicCommand(cmd.writeToBuffer());
                },
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    iconSize: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.remove, color: Colors.white70),
                    onPressed: () {
                      final cmd = BasicCommand(
                        climateControlCommand: ClimateControlCommand(
                          climateOn: isClimateOn,
                          targetTemperature: targetTemp - 0.5,
                        ),
                      );
                      ref
                          .read(vehicleStateProvider.notifier)
                          .sendBasicCommand(cmd.writeToBuffer());
                    },
                  ),
                  Text(
                    '${targetTemp.toStringAsFixed(1)}°',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  IconButton(
                    iconSize: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.add, color: Colors.white70),
                    onPressed: () {
                      final cmd = BasicCommand(
                        climateControlCommand: ClimateControlCommand(
                          climateOn: isClimateOn,
                          targetTemperature: targetTemp + 0.5,
                        ),
                      );
                      ref
                          .read(vehicleStateProvider.notifier)
                          .sendBasicCommand(cmd.writeToBuffer());
                    },
                  ),
                ],
              ),
              _buildClimateIconButton(
                icon: Icons.sensor_window,
                isActive: false,
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: Colors.grey.shade900,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    builder: (ctx) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.arrow_downward,
                            color: Colors.white,
                          ),
                          title: const Text(
                            'Vent Windows',
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: () {
                            final cmd = BasicCommand(
                              windowCommand: WindowCommand(
                                action: WindowCommand_WindowAction
                                    .WINDOW_ACTION_VENT,
                              ),
                            );
                            ref
                                .read(vehicleStateProvider.notifier)
                                .sendBasicCommand(cmd.writeToBuffer());
                            Navigator.pop(ctx);
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.arrow_upward,
                            color: Colors.white,
                          ),
                          title: const Text(
                            'Close Windows',
                            style: TextStyle(color: Colors.white),
                          ),
                          onTap: () {
                            final cmd = BasicCommand(
                              windowCommand: WindowCommand(
                                action: WindowCommand_WindowAction
                                    .WINDOW_ACTION_CLOSE,
                              ),
                            );
                            ref
                                .read(vehicleStateProvider.notifier)
                                .sendBasicCommand(cmd.writeToBuffer());
                            Navigator.pop(ctx);
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabeledClimateButton(
                icon: Icons.air,
                label: 'Windshield\nDefrost',
                isActive: isWindshieldDefrostOn,
                onTap: () {
                  final cmd = BasicCommand(
                    climateControlCommand: ClimateControlCommand(
                      climateOn: isClimateOn,
                      windshieldDefrostOn: !isWindshieldDefrostOn,
                    ),
                  );
                  ref
                      .read(vehicleStateProvider.notifier)
                      .sendBasicCommand(cmd.writeToBuffer());
                },
              ),
              _buildLabeledClimateButton(
                icon: Icons.grid_view,
                label: 'Rear\nDefrost',
                isActive: isRearDefrostOn,
                onTap: () {
                  final cmd = BasicCommand(
                    climateControlCommand: ClimateControlCommand(
                      climateOn: isClimateOn,
                      rearWindowDefrostOn: !isRearDefrostOn,
                    ),
                  );
                  ref
                      .read(vehicleStateProvider.notifier)
                      .sendBasicCommand(cmd.writeToBuffer());
                },
              ),
              _buildLabeledClimateButton(
                icon: Icons.radio_button_checked,
                label: 'Steering\nHeater',
                isActive: isSteeringHeaterOn,
                onTap: () {
                  final cmd = BasicCommand(
                    climateControlCommand: ClimateControlCommand(
                      climateOn: isClimateOn,
                      steeringWheelHeaterOn: !isSteeringHeaterOn,
                    ),
                  );
                  ref
                      .read(vehicleStateProvider.notifier)
                      .sendBasicCommand(cmd.writeToBuffer());
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClimateIconButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    double size = 56,
    double iconSize = 26,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isActive ? Colors.blue.shade700 : Colors.grey.shade800,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }

  Widget _buildLabeledClimateButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildClimateIconButton(icon: icon, isActive: isActive, onTap: onTap),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildSettingsMenu({bool shrinkWrap = false, ScrollPhysics? physics}) {
    return Container(
      color: Colors.black87,
      child: ListView(
        shrinkWrap: shrinkWrap,
        physics: physics,
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => setState(() => _currentSubMenu = null),
            ),
            title: const Text(
              'Settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const ListTile(
            title: Text(
              'Settings coming soon...',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: Colors.grey.shade800,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(color: Colors.white54))
            : null,
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: onTap,
      ),
    );
  }
}
