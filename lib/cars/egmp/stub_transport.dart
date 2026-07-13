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

  @override
  Future<void> send(AppToDevice message) async {
    if (!message.hasBasicCommandBytes()) return;

    final cmd = BasicCommand.fromBuffer(message.basicCommandBytes);
    if (cmd.whichAction() != BasicCommand_Action.doorLockCommand) return;

    final locked = cmd.doorLockCommand.lock;

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
    _emit(
      DeviceToApp(
        stateUpdate: StateUpdate(
          vehicleState: VehicleState(
            basicStateBytes: BasicState(areDoorsLocked: locked).writeToBuffer(),
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
