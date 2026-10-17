# Architecture

Flutter mobile app for an ESP32 car controller: BLE when near the car, MQTT (over LTE) when remote. `contracts/` is a git submodule with the protobuf definitions and TOML metadata shared with the firmware.

Related docs: [BLE & pairing](ble.md) · [Code generation](code-generation.md) · [Releases](releases.md)

## VehicleDefinition (`lib/models/vehicle_definition.dart`)
Abstract class tying constants, proto types, screen, and stub transport together. Concrete implementations live in `lib/cars/<vehicle>/` (currently `egmp` and `virtual_car`). Add a new one to `availableVehiclesProvider` (`lib/providers/selected_vehicle_provider.dart`) to register it.

Key methods: `decodeBasicState(bytes)`, `decodeAdvancedState(bytes)`, `buildDashboard()`, `createStubTransport()`.

## Wire protocol
`AppToDevice` / `DeviceToApp` envelopes carry vehicle-specific bytes. The receiver decodes using `platform_id` (a CRC32 from the vehicle's `meta.toml`). The same wire format is used over BLE and MQTT. State fields are `optional` — always **merge** updates: `_masterState.mergeFromMessage(incoming)`.

## Transport (`lib/transport/car_transport.dart`)
```dart
abstract class CarTransport {
  TransportType get transportType; // ble | mqtt | stub | http
  Stream<DeviceToApp> get messages;
  Future<void> send(AppToDevice message);
  void dispose();
}
```
*   `ble` / `stub` / `http` — full access (basic + advanced state/commands).
*   `mqtt` — basic state/commands only; `advanced_command_bytes` and `system_command` are BLE-only.

**Selection order (debug):** HTTP (if `transportPreference == http` in `pairedVehicleProvider`) → BLE (if `BleReady`) → MQTT. The HTTP branch is compiled away in release builds via `kDebugMode`. `vehicleStateProvider` uses `ref.watch(carTransportProvider)` to re-subscribe on transport switch.

## UI architecture
Entry: `main.dart` loads `PairedVehicleConfig` and the device ID at startup, then `AppEntryRouter` routes to `PairingWizardScreen` (unpaired) or `vehicle.buildDashboard()` (paired). It reacts to `pairedVehicleProvider`, so unpairing returns to the wizard automatically. The wizard currently uses the first entry of `availableVehiclesProvider`.

`lib/screens/vehicle_selection_screen.dart` is legacy and unused.

### Key providers

| Provider | Purpose |
|---|---|
| `availableVehiclesProvider` | All supported vehicles |
| `selectedVehicleProvider` | Computed from `pairedVehicleProvider`; null when unpaired |
| `pairedVehicleProvider` | Source of truth for pairing state (`PairedVehicleConfig?`) |
| `initialPairedVehicleConfigProvider` | Pre-loaded config override injected at startup |
| `bleConnectionProvider` | BLE connection lifecycle (`BleConnecting`/`BleReady`/`BleDisconnected`) |
| `bleSourceDeviceIdProvider` | Stable per-device BLE ID (overridden at startup) |
| `carTransportProvider` | Active transport instance |
| `transportTypeProvider` | Cheap `TransportType` watch for UI gating |
| `vehicleStateProvider` | `VehicleSnapshot` + `sendBasicCommand()` / `sendAdvancedCommand()` |

`VehicleSnapshot` fields (`basicState`, `advancedState`) are typed as `GeneratedMessage`; cast in the vehicle's own screen. They are decoded once per message and merged via `mergeFromMessage`.

### Per-vehicle screens (`lib/cars/<vehicle>/screens/`)
Transport gating pattern:
```dart
final isBle = transportType == TransportType.ble ||
              transportType == TransportType.stub ||
              transportType == TransportType.http;
```

Screen sections: **State** (always) | **Advanced State** (isBle) | **Controls** (always) | **Advanced Controls** (isBle).

## 3D viewer
The E-GMP dashboard renders the car with a Three.js viewer (`web_3d/`, bundled with Vite into `assets/web/` and shown in a `flutter_inappwebview`). See [`web_3d/README.md`](../web_3d/README.md). Source models are in `assets_src/`.
