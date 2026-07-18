import 'dart:async';

import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/transport/car_transport.dart';

class StubCarTransport implements CarTransport {
  @override
  TransportType get transportType => TransportType.stub;
  final _controller = StreamController<DeviceToApp>.broadcast();

  StubCarTransport() {
    // Emit initial state after listeners have had a chance to subscribe.
    Future.microtask(_emitInitialState);
  }

  void _emitInitialState() {
    final basicState = BasicState(
      odometer: 0,
      isDriving: false,
      areDoorsLocked: false,
    );
    final advancedState = AdvancedState(
      batteryVoltage: 800,
      gear: AdvancedState_Gear.GEAR_PARK,
    );
    final systemState = SystemState(
      firmwareVersion: 'egmp-stub-1.0.0',
      hardwareType: 'egmp',
      uptimeS: 0,
    );

    _emit(
      DeviceToApp(
        stateUpdate: StateUpdate(
          systemState: systemState,
          vehicleState: VehicleState(
            basicStateBytes: basicState.writeToBuffer(),
            advancedStateBytes: advancedState.writeToBuffer(),
          ),
        ),
      ),
    );
  }

  void _emit(DeviceToApp msg) {
    if (!_controller.isClosed) _controller.add(msg);
  }

  @override
  Stream<DeviceToApp> get messages => _controller.stream;

  bool _isLocked = false;
  bool _isChargePortOpen = false;
  bool _allDoorsOpen = false;
  bool _allWindowsOpen = false;
  bool _frunkTrunkOpen = false;

  @override
  Future<void> send(AppToDevice message) async {
    if (!message.hasBasicCommandBytes()) return;

    final cmd = BasicCommand.fromBuffer(message.basicCommandBytes);

    if (cmd.whichAction() == BasicCommand_Action.doorLockCommand) {
      _isLocked = cmd.doorLockCommand.lock;
      _allDoorsOpen = !_isLocked; // Unlock opens doors for testing
    } else if (cmd.whichAction() == BasicCommand_Action.chargePortCommand) {
      _isChargePortOpen = cmd.chargePortCommand.open;
    } else if (cmd.whichAction() == BasicCommand_Action.climateControlCommand) {
      // Hack: Use climate button to test windows
      _allWindowsOpen = cmd.climateControlCommand.climateOn;
    } else if (cmd.whichAction() == BasicCommand_Action.flashLightsCommand) {
      // Hack: Use lights button to test frunk/trunk
      // Since it's a stateless flash command, we'll just toggle them open for 3 seconds
      _frunkTrunkOpen = true;
      Future.delayed(const Duration(seconds: 3), () {
        _emitTestState(doors: _allDoorsOpen, windows: _allWindowsOpen, frunkTrunk: false, chargePort: _isChargePortOpen, locked: _isLocked);
      });
    }

    // Acknowledge the command.
    _emit(
      DeviceToApp(
        commandResponse: CommandResponse(
          messageId: message.messageId,
          success: true,
          statusCode: CommandStatusCode.COMMAND_STATUS_CODE_OK,
        ),
      ),
    );

    // Emit the resulting state update.
    _emitTestState(doors: _allDoorsOpen, windows: _allWindowsOpen, frunkTrunk: _frunkTrunkOpen, chargePort: _isChargePortOpen, locked: _isLocked);
  }

  void _emitTestState({required bool doors, required bool windows, required bool frunkTrunk, required bool chargePort, required bool locked}) {
    _emit(
      DeviceToApp(
        stateUpdate: StateUpdate(
          vehicleState: VehicleState(
            basicStateBytes: BasicState(
              areDoorsLocked: locked,
              isDriverDoorOpen: doors,
              isPassengerDoorOpen: doors,
              isRearLeftDoorOpen: doors,
              isRearRightDoorOpen: doors,
              isDriverWindowOpen: windows,
              isPassengerWindowOpen: windows,
              isRearLeftWindowOpen: windows,
              isRearRightWindowOpen: windows,
              isFrunkOpen: frunkTrunk,
              isTrunkOpen: frunkTrunk,
              chargePortState: chargePort ? BasicState_ChargePortState.CHARGE_PORT_STATE_OPEN : BasicState_ChargePortState.CHARGE_PORT_STATE_CLOSED,
            ).writeToBuffer(),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
  }
}
