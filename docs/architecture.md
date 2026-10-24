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

**Selection order (debug):** HTTP (if `transportPreference == http` in `pairedVehicleProvider`) → BLE (if `BleReady`) → MQTT. The HTTP branch is compiled away in release builds via `kDebugMode`. Android allows cleartext (plain HTTP) traffic only in debug builds: `android:usesCleartextTraffic` lives in `android/app/src/debug/AndroidManifest.xml`, not the main manifest. `vehicleStateProvider` uses `ref.watch(carTransportProvider)` to re-subscribe on transport switch.

## UI architecture
This section describes the screens as they are today. A shared dashboard that replaces the per-vehicle screens is specified in [UI design](ui.md), and support for several paired vehicles (which changes the single-vehicle pairing state described here) in [Other screens](ui-screens.md#vehicles).

Entry: `main.dart` loads `PairedVehicleConfig` and the device ID at startup, then `AppEntryRouter` routes to `PairingWizardScreen` (unpaired) or `vehicle.buildDashboard()` (paired). It reacts to `pairedVehicleProvider`, so unpairing returns to the wizard automatically. The wizard connects using the shared BLE service UUIDs, then picks the vehicle whose `platformId` matches the device's first message that carries one, so the stored `vehicleId` is always a supported `platformName`. If the stored `vehicleId` isn't supported by the build, `selectedVehicleProvider` is null and the wizard is shown.

### Platform mismatch
If a paired device later reports a different non-zero `platform_id`, `vehicleStateProvider` ignores its messages and sets `VehicleSnapshot.mismatchedPlatformId`. Dashboards show `PlatformMismatchBanner` (`lib/widgets/`), which offers to unpair. The app never unpairs on its own.

### Key providers

| Provider | Purpose |
|---|---|
| `availableVehiclesProvider` | All supported vehicles |
| `selectedVehicleProvider` | Computed from `pairedVehicleProvider`; null when unpaired or the vehicle is unsupported |
| `pairedVehicleProvider` | Source of truth for pairing state (`PairedVehicleConfig?`) |
| `initialPairedVehicleConfigProvider` | Pre-loaded config override injected at startup |
| `bleConnectionProvider` | BLE connection lifecycle (`BleConnecting`/`BleReady`/`BleDisconnected`) |
| `bleSourceDeviceIdProvider` | Stable per-device BLE ID (overridden at startup) |
| `carTransportProvider` | Active transport instance |
| `transportTypeProvider` | Cheap `TransportType` watch for UI gating |
| `vehicleStateProvider` | `VehicleSnapshot` + `sendBasicCommand()` / `sendAdvancedCommand()` |

`VehicleSnapshot` fields (`basicState`, `advancedState`) are typed as `GeneratedMessage`; cast in the vehicle's own screen. They are decoded once per message and merged via `mergeFromMessage`.

Commands complete when a `CommandResponse` with the same `message_id` arrives (15 s timeout). Command IDs start at a random value below 2^32 on each launch; MQTT heartbeats use IDs from 2^32 up so a response can never match a heartbeat. `CarTransport.send` throws `CarTransportException` when it can't send (e.g. MQTT offline, or an advanced command over MQTT), so the UI shows the error at once instead of waiting for the timeout.

`debugOverrideBasicState()` (debug builds only) replaces the basic state locally; the E-GMP debug drawer uses it to exercise the UI and 3D animations.

### Per-vehicle screens (`lib/cars/<vehicle>/screens/`)
Transport gating pattern:
```dart
final isBle = transportType == TransportType.ble ||
              transportType == TransportType.stub ||
              transportType == TransportType.http;
```

Screen sections: **State** (always) | **Advanced State** (isBle) | **Controls** (always) | **Advanced Controls** (isBle).

## 3D viewer
The E-GMP dashboard renders the car with a Three.js viewer (`web_3d/`, bundled with Vite into `assets/web/` and shown in a `flutter_inappwebview`). The page is served from the APK by Android's `WebViewAssetLoader` (`https://appassets.androidplatform.net/assets/flutter_assets/...`), not a local HTTP server.

Flutter only sends target state (`window.setVehicleState(...)`), and only when it changes. Fades, the power-flow pulse and hazard blinking are animated by the render loop in `app.js`. When the scene settles, the viewer saves a PNG snapshot (one per theme) to the app support directory. The snapshot is shown while the WebView boots and grayed out when the state is stale.

The runtime model is meshopt-compressed from an uncompressed export in `assets_src/`. See [`web_3d/README.md`](../web_3d/README.md).
