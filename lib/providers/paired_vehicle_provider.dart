import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/providers/connection_activity_provider.dart';

/// Holds the value loaded from SharedPreferences before [runApp].
/// Overridden in [ProviderScope] at app startup — never reads storage itself.
final initialPairedVehicleConfigProvider = Provider<PairedVehicleConfig?>(
  (_) => null,
);

class PairedVehicleNotifier extends Notifier<PairedVehicleConfig?> {
  @override
  PairedVehicleConfig? build() => ref.read(initialPairedVehicleConfigProvider);

  Future<void> pair(PairedVehicleConfig config) async {
    await config.save();
    state = config;
  }

  Future<void> unpair() async {
    final vehicleKey = state?.storageKey;
    await PairedVehicleConfig.clear();
    if (vehicleKey != null) {
      await ref
          .read(connectionActivityLogsProvider.notifier)
          .forget(vehicleKey);
    }
    state = null;
  }
}

final pairedVehicleProvider =
    NotifierProvider<PairedVehicleNotifier, PairedVehicleConfig?>(
      PairedVehicleNotifier.new,
    );

/// Whether the first-run wizard still has steps to show after pairing. While
/// it does, the router keeps showing the wizard, although a vehicle is paired.
///
/// Held in memory only: an app closed during those steps opens on the
/// dashboard, whose banners and settings offer the same set-up.
class WizardSetupPendingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void begin() => state = true;

  void finish() => state = false;
}

final wizardSetupPendingProvider =
    NotifierProvider<WizardSetupPendingNotifier, bool>(
      WizardSetupPendingNotifier.new,
    );
