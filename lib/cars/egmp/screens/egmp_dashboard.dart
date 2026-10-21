import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/providers/car_transport_provider.dart';
import 'package:open_car_app/transport/car_transport.dart';
import 'package:open_car_app/transport/http_transport.dart';
import 'package:open_car_app/providers/ble_connection_provider.dart';
import 'package:open_car_app/widgets/platform_mismatch_banner.dart';
import '../widgets/battery_menu.dart';
import '../widgets/debug_controls_drawer.dart';
import '../widgets/vehicle_3d_viewer.dart';

class EgmpDashboardScreen extends ConsumerStatefulWidget {
  const EgmpDashboardScreen({super.key});

  @override
  ConsumerState<EgmpDashboardScreen> createState() =>
      _EgmpDashboardScreenState();
}

class _EgmpDashboardScreenState extends ConsumerState<EgmpDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _vehicle3dViewerKey = GlobalKey();
  String? _currentSubMenu;
  String? _pendingAction;
  Timer? _timeUpdateTimer;

  @override
  void initState() {
    super.initState();
    _timeUpdateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timeUpdateTimer?.cancel();
    super.dispose();
  }

  void _executeCommand(String actionId, Future<void> Function() command) async {
    setState(() {
      _pendingAction = actionId;
    });

    try {
      await command();
    } catch (e) {
      if (mounted && _pendingAction == actionId) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted && _pendingAction == actionId) {
        setState(() {
          _pendingAction = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final transportType = ref.watch(transportTypeProvider);
    final isWideScreen = screenWidth > 800;

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: kDebugMode ? const DebugControlsDrawer() : null,
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () {
            if (kDebugMode) {
              _scaffoldKey.currentState?.openEndDrawer();
            }
          },
          child: const Text('E-GMP Platform'),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'simulate') {
                final transport = ref.read(carTransportProvider);
                if (transport is HttpCarTransport) {
                  try {
                    await transport.simulate();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Simulation error: $e')),
                      );
                    }
                  }
                }
              } else if (value == 'licenses') {
                showLicensePage(context: context, applicationName: 'Open Car');
              } else if (value == 'unpair') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Unpair vehicle?'),
                    content: const Text(
                      'This will remove the pairing and return you to the '
                      'setup wizard. The vehicle will also forget this phone '
                      '(factory reset required to re-pair).',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Unpair'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref.read(pairedVehicleProvider.notifier).unpair();
                }
              }
            },
            itemBuilder: (_) => [
              if (transportType == TransportType.http)
                const PopupMenuItem(
                  value: 'simulate',
                  child: ListTile(
                    leading: Icon(Icons.bug_report),
                    title: Text('Toggle Simulation'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'licenses',
                child: ListTile(
                  leading: Icon(Icons.description_outlined),
                  title: Text('Open-source licenses'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'unpair',
                child: ListTile(
                  leading: Icon(Icons.link_off),
                  title: Text('Unpair vehicle'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          const PlatformMismatchBanner(),
          Expanded(
            child: isWideScreen ? _buildWideLayout() : _buildNarrowLayout(),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout() {
    return RefreshIndicator(
      onRefresh: () async {
        final transportType = ref.read(transportTypeProvider);
        if (transportType == TransportType.ble) {
          ref.read(bleConnectionProvider.notifier).forceReconnect();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            SizedBox(height: 400, child: _buildVehicleRepresentation()),
            _buildRightPanel(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      children: [
        Expanded(
          child: Column(
            children: [Expanded(child: _buildVehicleRepresentation())],
          ),
        ),
        SizedBox(width: 350, child: _buildRightPanel()),
      ],
    );
  }

  Widget _buildVehicleRepresentation() {
    final state = ref.watch(vehicleStateProvider);
    final basicState = state.basicState as BasicState;

    final batterySoc = basicState.batterySoc;
    final batteryRange = basicState.batteryRangeKm;
    final powerFlow = basicState.powerFlowWatt;
    final isDriving = basicState.isDriving;
    final speed = basicState.speed;
    final chargePortState = basicState.chargePortState;

    final isLocked = basicState.areDoorsLocked;
    final isChargePortOpen =
        basicState.chargePortState ==
        BasicState_ChargePortState.CHARGE_PORT_STATE_OPEN;
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
        ? ' ${(powerFlow / 1000).toStringAsFixed(1)} kW'
        : '';

    // Like the cluster: the time to the charge limit, and on DC also the time to 80%.
    final bool isDcCharging =
        chargePortState ==
        BasicState_ChargePortState.CHARGE_PORT_STATE_DC_CHARGING;
    final bool hasLimit = isDcCharging
        ? basicState.hasDcChargeLimitPercent()
        : basicState.hasAcChargeLimitPercent();
    final int limit = isDcCharging
        ? basicState.dcChargeLimitPercent
        : basicState.acChargeLimitPercent;
    final String chargeStatusStr = isCharging
        ? [
            'Charging',
            if (basicState.timeRemainingMinutes > 0)
              '${_formatMinutes(basicState.timeRemainingMinutes)} to '
                  '${hasLimit ? '$limit%' : 'limit'}',
            if (isDcCharging &&
                basicState.timeTo80PercentMinutes > 0 &&
                !(hasLimit && limit == 80))
              '${_formatMinutes(basicState.timeTo80PercentMinutes)} to 80%',
          ].join(' • ')
        : (isV2L ? 'V2L Active' : '');

    // Advanced state only comes over BLE; a cached value could be long out of date.
    final advancedState = state.advancedState as AdvancedState;
    final String preconditioningStr = !state.isAdvancedStateLive
        ? ''
        : switch (advancedState.preconditioningState) {
            AdvancedState_PreconditioningState
                .PRECONDITIONING_STATE_PREPARING =>
              'Battery preconditioning: preparing',
            AdvancedState_PreconditioningState.PRECONDITIONING_STATE_HEATING =>
              'Battery preconditioning: heating',
            _ => '',
          };
    final String batteryStatusStr = [
      chargeStatusStr,
      preconditioningStr,
    ].where((s) => s.isNotEmpty).join(' • ');

    String statusLabel = 'Waiting for vehicle...';
    if (state.isStateLive) {
      statusLabel = 'Updated just now';
    } else if (state.lastUpdated != null) {
      final now = DateTime.now();
      final diff = now.difference(state.lastUpdated!);
      final localTime = state.lastUpdated!.toLocal();
      final isToday =
          now.year == localTime.year &&
          now.month == localTime.month &&
          now.day == localTime.day;
      if (diff.inHours >= 12 || !isToday) {
        final hours = localTime.hour.toString().padLeft(2, '0');
        final minutes = localTime.minute.toString().padLeft(2, '0');
        final month = localTime.month.toString().padLeft(2, '0');
        final day = localTime.day.toString().padLeft(2, '0');
        if (isToday) {
          statusLabel = 'Last synced: Today at $hours:$minutes';
        } else {
          statusLabel =
              'Last synced: ${localTime.year}-$month-$day $hours:$minutes';
        }
      } else if (diff.inHours > 0) {
        statusLabel = 'Last updated ${diff.inHours}h ago';
      } else if (diff.inMinutes > 0) {
        statusLabel = 'Last updated ${diff.inMinutes}m ago';
      } else {
        statusLabel = 'Last updated ${diff.inSeconds}s ago';
      }
    }

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Stack(
        children: [
          Positioned.fill(child: Vehicle3DViewer(key: _vehicle3dViewerKey)),
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
                      '${_formatRange(batteryRange, basicState)} - $batterySoc% 🔋$powerFlowStr',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (batteryStatusStr.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          batteryStatusStr,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        statusLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isDriving)
                  Text(
                    _formatSpeed(speed, basicState),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
          if (_currentSubMenu == 'climate')
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Text(
                'Vehicle Representation\n(Top-down interior view placeholder)',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
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
                    actionId: 'lock',
                    icon: isLocked ? Icons.lock : Icons.lock_open,
                    isActive: isLocked,
                    onPressed: () async {
                      final cmd = BasicCommand(
                        doorLockCommand: DoorLockCommand(lock: !isLocked),
                      );
                      await ref
                          .read(vehicleStateProvider.notifier)
                          .sendBasicCommand(cmd.writeToBuffer());
                    },
                  ),
                  const SizedBox(width: 16),
                  _buildQuickActionButton(
                    actionId: 'charge_port',
                    icon: isChargePortOpen
                        ? Icons.ev_station
                        : Icons.ev_station_outlined,
                    isActive: isChargePortOpen,
                    onPressed: () async {
                      final cmd = BasicCommand(
                        chargePortCommand: ChargePortCommand(
                          open: !isChargePortOpen,
                        ),
                      );
                      await ref
                          .read(vehicleStateProvider.notifier)
                          .sendBasicCommand(cmd.writeToBuffer());
                    },
                  ),
                  const SizedBox(width: 16),
                  _buildQuickActionButton(
                    actionId: 'lights',
                    icon: Icons.highlight,
                    // Flashing is momentary; there's no on/off state to show.
                    isActive: false,
                    onPressed: () async {
                      final cmd = BasicCommand(
                        flashLightsCommand: FlashLightsCommand(),
                      );
                      await ref
                          .read(vehicleStateProvider.notifier)
                          .sendBasicCommand(cmd.writeToBuffer());
                    },
                  ),
                  const SizedBox(width: 16),
                  _buildQuickActionButton(
                    actionId: 'climate',
                    icon: Icons.ac_unit,
                    isActive: isClimateOn,
                    onPressed: () async {
                      final cmd = BasicCommand(
                        climateControlCommand: ClimateControlCommand(
                          climateOn: !isClimateOn,
                        ),
                      );
                      await ref
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
    required String actionId,
    required IconData icon,
    required bool isActive,
    required Future<void> Function() onPressed,
  }) {
    final isLoading = _pendingAction == actionId;
    return InkWell(
      onTap: isLoading ? null : () => _executeCommand(actionId, onPressed),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: isLoading
            ? SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: isActive
                      ? Theme.of(context).colorScheme.onPrimaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : Icon(
                icon,
                color: isActive
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 32,
              ),
      ),
    );
  }

  Widget _buildRightPanel({bool shrinkWrap = false, ScrollPhysics? physics}) {
    if (_currentSubMenu == 'climate') {
      return _buildClimateMenu(shrinkWrap: shrinkWrap, physics: physics);
    } else if (_currentSubMenu == 'battery') {
      return _buildBatteryMenu(shrinkWrap: shrinkWrap, physics: physics);
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
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: ListView(
        shrinkWrap: shrinkWrap,
        physics: physics,
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        children: [
          _buildMenuTile(
            icon: Icons.ac_unit,
            title: 'Climate & Windows',
            subtitle:
                'Indoor: ${_formatTemperature(basicState.indoorTemperature, basicState)}',
            onTap: () => setState(() => _currentSubMenu = 'climate'),
          ),
          _buildMenuTile(
            icon: Icons.battery_charging_full,
            title: 'Battery & Drivetrain',
            subtitle: state.isAdvancedStateLive ? null : 'Not live',
            onTap: () => setState(() => _currentSubMenu = 'battery'),
          ),
          _buildMenuTile(
            icon: Icons.settings,
            title: 'About & Settings',
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
    final targetTemp = basicState.hasTargetClimateTemperature()
        ? basicState.targetClimateTemperature
        : 22.0;
    final isWindshieldDefrostOn = basicState.isWindshieldDefrostOn;
    final isRearDefrostOn = basicState.isRearWindowDefrostOn;
    final isSteeringHeaterOn = basicState.isSteeringWheelHeaterOn;
    final driverSeat = basicState.driverSeatClimate;
    final passengerSeat = basicState.passengerSeatClimate;
    final outdoorTemp = basicState.outdoorTemperature;
    final indoorTemp = basicState.indoorTemperature;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: ListView(
        shrinkWrap: shrinkWrap,
        physics: physics,
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => setState(() => _currentSubMenu = null),
            ),
            title: Text(
              'Climate & Windows',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Outdoor: ${_formatTemperature(outdoorTemp, basicState)}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Indoor: ${_formatTemperature(indoorTemp, basicState)}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildClimateIconButton(
                actionId: 'climate_power',
                icon: Icons.power_settings_new,
                isActive: isClimateOn,
                onTap: () async {
                  final cmd = BasicCommand(
                    climateControlCommand: ClimateControlCommand(
                      climateOn: !isClimateOn,
                    ),
                  );
                  await ref
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
                    icon: _pendingAction == 'temp_down'
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.remove,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                    onPressed: _pendingAction == 'temp_down'
                        ? null
                        : () {
                            _executeCommand('temp_down', () async {
                              final cmd = BasicCommand(
                                climateControlCommand: ClimateControlCommand(
                                  climateOn: isClimateOn,
                                  targetTemperature: targetTemp - 0.5,
                                ),
                              );
                              await ref
                                  .read(vehicleStateProvider.notifier)
                                  .sendBasicCommand(cmd.writeToBuffer());
                            });
                          },
                  ),
                  Text(
                    _formatTargetTemperature(targetTemp, basicState),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  IconButton(
                    iconSize: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(),
                    icon: _pendingAction == 'temp_up'
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.add,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                    onPressed: _pendingAction == 'temp_up'
                        ? null
                        : () {
                            _executeCommand('temp_up', () async {
                              final cmd = BasicCommand(
                                climateControlCommand: ClimateControlCommand(
                                  climateOn: isClimateOn,
                                  targetTemperature: targetTemp + 0.5,
                                ),
                              );
                              await ref
                                  .read(vehicleStateProvider.notifier)
                                  .sendBasicCommand(cmd.writeToBuffer());
                            });
                          },
                  ),
                ],
              ),
              _buildClimateIconButton(
                actionId: 'window_vent',
                icon: Icons.sensor_window,
                isActive: false,
                onTap: () async {
                  final action = await _pickWindowAction();
                  if (action == null) return;
                  final cmd = BasicCommand(
                    windowCommand: WindowCommand(action: action),
                  );
                  await ref
                      .read(vehicleStateProvider.notifier)
                      .sendBasicCommand(cmd.writeToBuffer());
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
                actionId: 'windshield_defrost',
                icon: Icons.air,
                label: 'Windshield\nDefrost',
                isActive: isWindshieldDefrostOn,
                onTap: () async {
                  final cmd = BasicCommand(
                    climateControlCommand: ClimateControlCommand(
                      climateOn: isClimateOn,
                      windshieldDefrostOn: !isWindshieldDefrostOn,
                    ),
                  );
                  await ref
                      .read(vehicleStateProvider.notifier)
                      .sendBasicCommand(cmd.writeToBuffer());
                },
              ),
              _buildLabeledClimateButton(
                actionId: 'rear_defrost',
                icon: Icons.grid_view,
                label: 'Rear\nDefrost',
                isActive: isRearDefrostOn,
                onTap: () async {
                  final cmd = BasicCommand(
                    climateControlCommand: ClimateControlCommand(
                      climateOn: isClimateOn,
                      rearWindowDefrostOn: !isRearDefrostOn,
                    ),
                  );
                  await ref
                      .read(vehicleStateProvider.notifier)
                      .sendBasicCommand(cmd.writeToBuffer());
                },
              ),
              _buildLabeledClimateButton(
                actionId: 'steering_heater',
                icon: Icons.radio_button_checked,
                label: 'Steering\nHeater',
                isActive: isSteeringHeaterOn,
                onTap: () async {
                  final cmd = BasicCommand(
                    climateControlCommand: ClimateControlCommand(
                      climateOn: isClimateOn,
                      steeringWheelHeaterOn: !isSteeringHeaterOn,
                    ),
                  );
                  await ref
                      .read(vehicleStateProvider.notifier)
                      .sendBasicCommand(cmd.writeToBuffer());
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabeledClimateButton(
                actionId: 'driver_seat',
                icon: Icons.event_seat,
                label: 'Driver Seat\n${_seatLabel(driverSeat)}',
                isActive: _isSeatOn(driverSeat),
                onTap: () async {
                  final cmd = BasicCommand(
                    climateControlCommand: ClimateControlCommand(
                      climateOn: isClimateOn,
                      driverSeatClimate: _nextSeatClimate(driverSeat),
                    ),
                  );
                  await ref
                      .read(vehicleStateProvider.notifier)
                      .sendBasicCommand(cmd.writeToBuffer());
                },
              ),
              _buildLabeledClimateButton(
                actionId: 'passenger_seat',
                icon: Icons.event_seat,
                label: 'Passenger Seat\n${_seatLabel(passengerSeat)}',
                isActive: _isSeatOn(passengerSeat),
                onTap: () async {
                  final cmd = BasicCommand(
                    climateControlCommand: ClimateControlCommand(
                      climateOn: isClimateOn,
                      passengerSeatClimate: _nextSeatClimate(passengerSeat),
                    ),
                  );
                  await ref
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

  /// Asks which window action to run; null when dismissed.
  Future<WindowCommand_WindowAction?> _pickWindowAction() {
    final colors = Theme.of(context).colorScheme;
    Widget option(IconData icon, String label, WindowCommand_WindowAction a) {
      return ListTile(
        leading: Icon(icon, color: colors.onSurface),
        title: Text(label, style: TextStyle(color: colors.onSurface)),
        onTap: () => Navigator.pop(context, a),
      );
    }

    return showModalBottomSheet<WindowCommand_WindowAction>(
      context: context,
      backgroundColor: colors.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(
            Icons.arrow_downward,
            'Vent Windows',
            WindowCommand_WindowAction.WINDOW_ACTION_VENT,
          ),
          option(
            Icons.arrow_upward,
            'Close Windows',
            WindowCommand_WindowAction.WINDOW_ACTION_CLOSE,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildClimateIconButton({
    required String actionId,
    required IconData icon,
    required bool isActive,
    required Future<void> Function() onTap,
    double size = 56,
    double iconSize = 26,
  }) {
    final isLoading = _pendingAction == actionId;
    return InkWell(
      onTap: isLoading ? null : () => _executeCommand(actionId, onTap),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: isLoading
            ? Center(
                child: SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: isActive
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : Icon(
                icon,
                color: isActive
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                size: iconSize,
              ),
      ),
    );
  }

  static bool _isSeatOn(BasicState_SeatClimate seat) =>
      seat != BasicState_SeatClimate.SEAT_CLIMATE_OFF &&
      seat != BasicState_SeatClimate.SEAT_CLIMATE_UNSPECIFIED;

  static String _seatLabel(BasicState_SeatClimate seat) => switch (seat) {
    BasicState_SeatClimate.SEAT_CLIMATE_HEAT_LEVEL_1 => 'Level 1',
    BasicState_SeatClimate.SEAT_CLIMATE_HEAT_LEVEL_2 => 'Level 2',
    BasicState_SeatClimate.SEAT_CLIMATE_HEAT_LEVEL_3 => 'Level 3',
    BasicState_SeatClimate.SEAT_CLIMATE_OFF => 'Off',
    _ => '--',
  };

  /// The next level as the car's seat button steps them: off, 3, 2, 1, off.
  static BasicState_SeatClimate _nextSeatClimate(BasicState_SeatClimate seat) =>
      switch (seat) {
        BasicState_SeatClimate.SEAT_CLIMATE_HEAT_LEVEL_3 =>
          BasicState_SeatClimate.SEAT_CLIMATE_HEAT_LEVEL_2,
        BasicState_SeatClimate.SEAT_CLIMATE_HEAT_LEVEL_2 =>
          BasicState_SeatClimate.SEAT_CLIMATE_HEAT_LEVEL_1,
        BasicState_SeatClimate.SEAT_CLIMATE_HEAT_LEVEL_1 =>
          BasicState_SeatClimate.SEAT_CLIMATE_OFF,
        _ => BasicState_SeatClimate.SEAT_CLIMATE_HEAT_LEVEL_3,
      };

  Widget _buildLabeledClimateButton({
    required String actionId,
    required IconData icon,
    required String label,
    required bool isActive,
    required Future<void> Function() onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildClimateIconButton(
          actionId: actionId,
          icon: icon,
          isActive: isActive,
          onTap: onTap,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsMenu({bool shrinkWrap = false, ScrollPhysics? physics}) {
    final state = ref.watch(vehicleStateProvider);
    final basicState = state.basicState as BasicState;

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: ListView(
        shrinkWrap: shrinkWrap,
        physics: physics,
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () => setState(() => _currentSubMenu = null),
            ),
            title: Text(
              'About & Settings',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Odometer'),
            trailing: Text(
              _formatOdometer(basicState.odometer, basicState),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const Divider(),
          ListTile(
            title: Text(
              'Settings coming soon...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _isBle {
    final transportType = ref.watch(transportTypeProvider);
    return transportType == TransportType.ble ||
        transportType == TransportType.stub ||
        transportType == TransportType.http;
  }

  Widget _buildBatteryMenu({bool shrinkWrap = false, ScrollPhysics? physics}) {
    final state = ref.watch(vehicleStateProvider);
    final basicState = state.basicState as BasicState;
    return BatteryMenu(
      advancedState: state.advancedState as AdvancedState,
      isLive: state.isAdvancedStateLive,
      formatTemperature: (celsius) => _formatTemperature(celsius, basicState),
      onBack: () => setState(() => _currentSubMenu = null),
      onPreconditioningChanged: _isBle
          ? (enable) => _executeCommand('preconditioning', () async {
              final cmd = AdvancedCommand(
                batteryPreconditioningCommand: BatteryPreconditioningCommand(
                  enable: enable,
                ),
              );
              await ref
                  .read(vehicleStateProvider.notifier)
                  .sendAdvancedCommand(cmd.writeToBuffer());
            })
          : null,
      isPreconditioningPending: _pendingAction == 'preconditioning',
      shrinkWrap: shrinkWrap,
      physics: physics,
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }
}

String _formatMinutes(int minutes) =>
    minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min';

const double _kmPerMile = 1.609344;

bool _isMiles(BasicState s) =>
    s.distanceUnit == BasicState_DistanceUnit.DISTANCE_UNIT_MILES;

/// Distances and speeds arrive in km and km/h; show them in the unit the car displays.
/// The cluster rounds the range (336 km is 209 mi) but truncates the odometer (22916 km
/// is 14239 mi).
String _formatRange(int km, BasicState s) =>
    _isMiles(s) ? '${(km / _kmPerMile).round()} mi' : '$km km';

String _formatOdometer(int km, BasicState s) =>
    _isMiles(s) ? '${(km / _kmPerMile).floor()} mi' : '$km km';

/// The speed arrives in whole km/h, so it can be 1 mph off the cluster.
String _formatSpeed(int kmh, BasicState s) =>
    _isMiles(s) ? '${(kmh / _kmPerMile).round()} mph' : '$kmh km/h';

bool _isFahrenheit(BasicState s) =>
    s.temperatureUnit == BasicState_TemperatureUnit.TEMPERATURE_UNIT_FAHRENHEIT;

/// Temperatures arrive in Celsius; show them in the unit the car displays.
String _formatTemperature(double celsius, BasicState s) => _isFahrenheit(s)
    ? '${(celsius * 9 / 5 + 32).round()}°F'
    : '${celsius.toStringAsFixed(1)}°C';

/// The climate target steps 1 °F per 0.5 °C (17 °C is 62 °F, 27 °C is 82 °F), so a plain
/// conversion wouldn't match what the car shows.
String _formatTargetTemperature(double celsius, BasicState s) =>
    _isFahrenheit(s)
    ? '${((celsius - 14) * 2 + 56).round()}°'
    : '${celsius.toStringAsFixed(1)}°';
