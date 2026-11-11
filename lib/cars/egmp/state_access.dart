import 'package:open_car_app/generated/opencar/cars/egmp/v1/egmp.pb.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';

/// The E-GMP basic state of [s].
BasicState egmpBasic(VehicleSnapshot s) => s.basicState as BasicState;

/// The E-GMP advanced state of [s], only while it is live over this transport.
AdvancedState? egmpAdvanced(VehicleSnapshot s) =>
    s.isAdvancedStateLive ? s.advancedState as AdvancedState : null;

/// A reported flag, or null when the car hasn't reported it.
bool? reportedFlag(bool has, bool value) => has ? value : null;
