import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/connection_activity_provider.dart';
import 'package:open_car_app/providers/dashboard_layout_provider.dart';
import 'package:open_car_app/providers/vehicle_summary_provider.dart';

/// Holds the value loaded from SharedPreferences before [runApp].
/// Overridden in [ProviderScope] at app startup — never reads storage itself.
final initialPairedVehiclesProvider = Provider<PairedVehicles>(
  (_) => const PairedVehicles(),
);

class PairedVehiclesNotifier extends Notifier<PairedVehicles> {
  /// Writes run one at a time, so an older list can't replace a newer one.
  Future<void> _lastWrite = Future.value();

  @override
  PairedVehicles build() => ref.read(initialPairedVehiclesProvider);

  Future<void> _commit(PairedVehicles next) {
    state = next;
    return _lastWrite = _lastWrite.then(
      (_) => next.save(),
      onError: (_) => next.save(),
    );
  }

  /// Adds [config] and makes it current. Pairing a device again replaces its
  /// entry, keeping its id and name and so what is stored for it.
  Future<void> pair(PairedVehicleConfig config) async {
    PairedVehicleConfig? existing;
    for (final vehicle in state.vehicles) {
      if (vehicle.id == config.id || vehicle.isSameDevice(config)) {
        existing = vehicle;
        break;
      }
    }
    final paired = existing == null
        ? config
        : config.copyWith(
            id: existing.id,
            name: existing.name,
            clearName: existing.name == null,
          );
    await _commit(
      PairedVehicles(
        vehicles: existing == null
            ? [...state.vehicles, paired]
            : [
                for (final vehicle in state.vehicles)
                  vehicle.id == existing.id ? paired : vehicle,
              ],
        currentId: paired.id,
      ),
    );
  }

  /// Makes the vehicle with [id] current. Its providers rebuild for it, ending
  /// the previous vehicle's links first.
  Future<void> switchTo(String id) async {
    if (id == state.current?.id || !state.vehicles.any((v) => v.id == id)) {
      return;
    }
    await _commit(PairedVehicles(vehicles: state.vehicles, currentId: id));
  }

  /// Names the vehicle with [id]. A blank [name] goes back to the platform's.
  Future<void> rename(String id, String name) {
    final trimmed = name.trim();
    return _update(
      id,
      (vehicle) => vehicle.copyWith(
        name: trimmed.isEmpty ? null : trimmed,
        clearName: trimmed.isEmpty,
      ),
    );
  }

  /// Remembers the MQTT client ID the current vehicle's device reported. The
  /// device repeats it, so this does nothing unless it changed.
  Future<void> setMqttClientId(String clientId) async {
    final current = state.current;
    if (current == null || current.mqttClientId == clientId) return;
    await _update(
      current.id,
      (vehicle) => vehicle.copyWith(mqttClientId: clientId),
    );
  }

  Future<void> _update(
    String id,
    PairedVehicleConfig Function(PairedVehicleConfig) change,
  ) => _commit(
    PairedVehicles(
      vehicles: [
        for (final vehicle in state.vehicles)
          vehicle.id == id ? change(vehicle) : vehicle,
      ],
      currentId: state.currentId,
    ),
  );

  /// Removes the vehicle with [id], or the current one, and everything stored
  /// for it. Unpairing the current vehicle makes the first remaining one
  /// current; with none left, the router shows the wizard.
  Future<void> unpair([String? id]) async {
    final target = id ?? state.current?.id;
    if (target == null || !state.vehicles.any((v) => v.id == target)) return;
    final remaining = [
      for (final vehicle in state.vehicles)
        if (vehicle.id != target) vehicle,
    ];
    await _commit(
      PairedVehicles(
        vehicles: remaining,
        currentId: state.current?.id == target
            ? remaining.firstOrNull?.id
            : state.currentId,
      ),
    );
    await Future.wait([
      ref.read(connectionActivityLogsProvider.notifier).forget(target),
      ref.read(savedLayoutsProvider.notifier).forget(target),
      ref.read(unsupportedCommandsProvider.notifier).forget(target),
      ref.read(vehicleSummariesProvider.notifier).forget(target),
    ]);
  }
}

final pairedVehiclesProvider =
    NotifierProvider<PairedVehiclesNotifier, PairedVehicles>(
      PairedVehiclesNotifier.new,
    );

/// The current vehicle; null when none is paired. Change it through
/// [pairedVehiclesProvider].
final pairedVehicleProvider = Provider<PairedVehicleConfig?>(
  (ref) => ref.watch(pairedVehiclesProvider).current,
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
