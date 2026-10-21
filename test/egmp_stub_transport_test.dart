import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_car_app/cars/egmp/stub_transport.dart';
import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';

AdvancedState_PreconditioningState? _preconditioning(DeviceToApp msg) {
  if (!msg.hasStateUpdate() || !msg.stateUpdate.hasVehicleState()) return null;
  final bytes = msg.stateUpdate.vehicleState.advancedStateBytes;
  if (bytes.isEmpty) return null;
  final state = AdvancedState.fromBuffer(bytes);
  return state.hasPreconditioningState() ? state.preconditioningState : null;
}

void main() {
  test('preconditioning goes through preparing, then heating', () async {
    final transport = StubCarTransport();
    addTearDown(transport.dispose);
    final seen = <AdvancedState_PreconditioningState>[];
    final responses = <CommandResponse>[];
    transport.messages.listen((msg) {
      final state = _preconditioning(msg);
      if (state != null) seen.add(state);
      if (msg.hasCommandResponse()) responses.add(msg.commandResponse);
    });
    await Future<void>.delayed(Duration.zero);

    await transport.send(
      AppToDevice(
        messageId: Int64(7),
        advancedCommandBytes: AdvancedCommand(
          batteryPreconditioningCommand: BatteryPreconditioningCommand(
            enable: true,
          ),
        ).writeToBuffer(),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(responses.single.messageId, Int64(7));
    expect(
      seen.last,
      AdvancedState_PreconditioningState.PRECONDITIONING_STATE_PREPARING,
    );

    await Future<void>.delayed(const Duration(seconds: 3, milliseconds: 100));
    expect(
      seen.last,
      AdvancedState_PreconditioningState.PRECONDITIONING_STATE_HEATING,
    );

    await transport.send(
      AppToDevice(
        messageId: Int64(8),
        advancedCommandBytes: AdvancedCommand(
          batteryPreconditioningCommand: BatteryPreconditioningCommand(
            enable: false,
          ),
        ).writeToBuffer(),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      seen.last,
      AdvancedState_PreconditioningState.PRECONDITIONING_STATE_OFF,
    );
  });
}
