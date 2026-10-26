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
| `vehicleStateProvider` | `VehicleSnapshot` + `sendBasicCommand()` / `sendAdvancedCommand()` / `sendSystemCommand()` (BLE only) |
| `canAccessStateProvider` | The device's CAN access state (`SystemState.can_access`), from the current connection only: null until reported on it, cleared on every transport or connection change, never cached |
| `canAccessActionsProvider` | Approves or withdraws vehicle control and toggles the developer write lock |
| `commandAvailabilityProvider` | Which commands the device accepts now (`SystemState.command_availability`), from the current connection only: null until reported on it, cleared on every transport or connection change and when the device goes quiet, never cached. Over MQTT it covers the basic commands |
| `commandUiStateProvider` | `enabled`, `disabled` (greyed out) or `hidden` for one command, from the availability |

`VehicleSnapshot` fields (`basicState`, `advancedState`) are typed as `GeneratedMessage`; cast in the vehicle's own screen. They are decoded once per message and merged via `mergeFromMessage`.

Commands complete when a `CommandResponse` with the same `message_id` arrives (15 s timeout). Command IDs start at a random value below 2^32 on each launch; MQTT heartbeats use IDs from 2^32 up so a response can never match a heartbeat. `CarTransport.send` throws `CarTransportException` when it can't send (e.g. MQTT offline, or an advanced command over MQTT), so the UI shows the error at once instead of waiting for the timeout.

`debugOverrideBasicState()` (debug builds only) replaces the basic state locally; the E-GMP debug drawer uses it to exercise the UI and 3D animations.

### Vehicle control (CAN read-write)
The device only listens to the car until three things hold (firmware `docs/can.md`, "Read-write policy"): it has identified the car, the owner has approved control of that car, and, in development firmware builds, the developer write lock is unlocked (it locks again at every restart). The app reads why from `canAccessStateProvider` and changes it with `canAccessActionsProvider`, both over BLE only:

*   `CanAccessBanner` (`lib/widgets/`) appears when the car is identified but control isn't approved, or was approved for a different car, and opens the approval dialog. Both dashboards show it under `BleBondLostBanner`.
*   `showCanReadWriteApprovalDialog` shows the risks and only sends the approval once the owner ticks "I understand the risks". The approval belongs to the car the device is plugged into; the device keeps it across restarts and phone changes.
*   `CanAccessSection` shows the state and the reason in words (`canAccessSummary`), approving and withdrawing the approval, and the developer write lock switch when the firmware reports `dev_lock_available`. The E-GMP dashboard shows it in "About & Settings", the virtual-car dashboard above its controls.

`canAccessStateProvider` listens to the transport itself rather than reading `VehicleSnapshot.system`: the snapshot is restored across transport switches and cached across restarts, so its `can_access` could show "Control enabled" for a device that has since restarted read-only. The device repeats the access state every few seconds, so a new connection gets it quickly.

While the device is read-only it refuses basic and advanced commands with a failed `CommandResponse` whose message gives the reason (e.g. "command rejected: the device is read-only: the developer write lock is locked"); the command's future fails with that message. The dashboards send commands through `sendVehicleCommand` (`lib/widgets/vehicle_command_feedback.dart`), which shows the reason in a SnackBar, with a "Review" action opening the approval dialog when control still needs approving.

The device never sends the car's VIN or fingerprint, so the dialog can't name the car.

### Command availability
The device decides which commands it accepts right now and reports it (firmware `docs/commands.md`, "Command availability"): `SystemState.command_availability`, over BLE and over MQTT (basic commands only), repeated every few seconds. The app greys out the buttons of commands the device doesn't accept, with no reason shown, and hides the ones reported `UNSUPPORTED` (not on this car; nothing sends that yet). The device rejects an unavailable command with `COMMAND_STATUS_CODE_REJECTED_UNAVAILABLE` even if the app sends it anyway, and `sendVehicleCommand` shows its reason.

*   Commands are identified by their field number in the vehicle's `BasicCommand` / `AdvancedCommand` oneof. Each vehicle keeps them in `lib/cars/<vehicle>/command_ids.dart`, read from the generated messages with `commandId` so they can't drift from the contracts. Every vehicle button needs an entry there and a `commandUiStateProvider` check; a new command is greyed out over BLE until the device lists it.
*   Like `canAccessStateProvider`, `commandAvailabilityProvider` listens to the transport itself and never reads the cached snapshot, so a cached "available" can't enable a button. It is cleared when the device goes quiet: after `kCommandAvailabilityStaleAfter` over BLE (15 s, three missed repeats of the 5 s repeat) and after `kStateLivenessTimeout` over MQTT (30 s, the same as the vehicle state going stale), since MQTT is synced slower and less often.
*   Over BLE and MQTT a command is enabled only while the device says it accepts it, so the buttons are greyed out right after connecting until the first report. While MQTT commands are not authenticated the device reports every command unavailable over MQTT. The stub and HTTP debug transports may not report anything, so there the buttons stay enabled and the device rejects what it can't do.

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
