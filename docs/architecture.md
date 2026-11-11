# Architecture

Flutter mobile app for an ESP32 car controller: BLE when near the car, MQTT (over LTE) when remote. `contracts/` is a git submodule with the protobuf definitions and TOML metadata shared with the firmware.

Related docs: [BLE & pairing](ble.md) · [Code generation](code-generation.md) · [Releases](releases.md)

## VehicleDefinition (`lib/models/vehicle_definition.dart`)
Abstract class tying constants, proto types, the dashboard description and the stub transport together. Concrete implementations live in `lib/cars/<vehicle>/` (currently `egmp` and `virtual_car`). Add a new one to `availableVehiclesProvider` (`lib/providers/selected_vehicle_provider.dart`) to register it.

Key methods: `decodeBasicState(bytes)`, `decodeAdvancedState(bytes)`, `buildHero(context, snapshot)`, `buildDebugDrawer()` (debug builds only), `createStubTransport()`. A definition also returns its `skin` (see [Theming](ui-theming.md)).

It also describes the vehicle for the shared dashboard ([Vehicle description](ui.md#vehicle-description)): its display name and platform label, hero, display units, energy stores, header status line, climate, its tile catalog (`lib/models/tile_catalog.dart`) and a default layout per tier. Tiles carry data accessors and commands, not widgets, so the shared tile widgets draw every platform alike; only chart tiles bring their own builder. `test/vehicle_catalog_test.dart` checks every registered vehicle's catalog and layouts.

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

**Selection order (debug):** HTTP (if `transportPreference == http` in `pairedVehicleProvider`) → BLE (if `BleReady`) → MQTT, once the device has reported its `mqtt_client_id` over a local link. That ID fills the `{client_id}` of the topic templates and is stored with the pairing; the app connects to the broker under its own ID. The HTTP branch is compiled away in release builds via `kDebugMode`. Android allows cleartext (plain HTTP) traffic only in debug builds: `android:usesCleartextTraffic` lives in `android/app/src/debug/AndroidManifest.xml`, not the main manifest. `vehicleStateProvider` uses `ref.watch(carTransportProvider)` to re-subscribe on transport switch.

## UI architecture
Every vehicle shares one dashboard, built from its description; the design is in [UI design](ui.md). Support for several paired vehicles (which changes the single-vehicle pairing state described here) is specified in [Other screens](ui-screens.md#vehicles).

Entry: `main.dart` loads `PairedVehicles` and the device ID at startup, then `AppEntryRouter` routes to `PairingWizardScreen` (unpaired) or `DashboardScreen` (paired). It reacts to `pairedVehicleProvider`, so unpairing returns to the wizard automatically. The wizard connects using the shared BLE service UUIDs, then picks the vehicle whose `platformId` matches the device's first message that carries one, so the stored `vehicleId` is always a supported `platformName`. The first-run wizard stays up after pairing for its set-up steps (`wizardSetupPendingProvider`), and takes the vehicle's skin as soon as it is paired. If the stored `vehicleId` isn't supported by the build, `selectedVehicleProvider` is null and the wizard is shown.

### Platform mismatch
**Several vehicles:** only the current vehicle has live links and live state. Switching rebuilds the providers that depend on its id, and each one ends the previous vehicle's link first: `bleConnectionProvider` waits for the old connection to be cancelled before connecting. Everything stored per vehicle is keyed by `storageKey`, which is the vehicle's id, so two vehicles of the same platform stay apart. An install from before several vehicles were supported migrates on first launch and keeps its platform name as its id, so what it had stored stays its own. Pairing a device that is already in the list replaces its entry, keeping its id and name. Unpairing deletes everything stored for that vehicle.

If a paired device later reports a different non-zero `platform_id`, `vehicleStateProvider` ignores its messages and sets `VehicleSnapshot.mismatchedPlatformId`. The dashboard's banner slot then shows a banner that offers to unpair. The app never unpairs on its own.

### Key providers

| Provider | Purpose |
|---|---|
| `availableVehiclesProvider` | All supported vehicles |
| `selectedVehicleProvider` | Computed from `pairedVehicleProvider`; null when unpaired or the vehicle is unsupported |
| `pairedVehiclesProvider` | Source of truth for pairing state (`PairedVehicles`: the list and the current vehicle's id); pairs, switches, renames and unpairs |
| `pairedVehicleProvider` | The current vehicle's `PairedVehicleConfig?` |
| `initialPairedVehiclesProvider` | Pre-loaded state injected at startup |
| `currentVehicleNameProvider` | The user's name for the current vehicle, or its platform's |
| `vehicleListProvider` | Every paired vehicle with its name, platform, last known `VehicleSummary` and whether it is current, for the switcher and the Vehicles screen |
| `vehicleSummariesProvider` | Each vehicle's last known level, range and update, by `storageKey`, for the vehicle lists |
| `bleConnectionProvider` | BLE connection lifecycle (`BleConnecting`/`BleReady`/`BleDisconnected`) |
| `bleSourceDeviceIdProvider` | Stable per-device BLE ID (overridden at startup) |
| `carTransportProvider` | Active transport instance |
| `transportTypeProvider` | Cheap `TransportType` watch for UI gating |
| `themeModeProvider` | The user's theme mode (system, light, dark), saved in `SharedPreferences` |
| `initialThemeModeProvider` | Pre-loaded theme mode override injected at startup |
| `currentSkinProvider` | The current vehicle's skin, or the default one when no vehicle is known |
| `vehicleStateProvider` | `VehicleSnapshot` + `sendBasicCommand()` / `sendAdvancedCommand()` / `sendSystemCommand()` (BLE only) |
| `canAccessStateProvider` | The device's CAN access state (`SystemState.can_access`), from the current connection only: null until reported on it, cleared on every transport or connection change, never cached |
| `canAccessActionsProvider` | Approves or withdraws vehicle control and toggles the developer write lock |
| `phoneAccessStateProvider` | What the device allows this phone (`SystemState.phone_access`): its trust level, whether the car has a validated phone, its validation session. From the current connection only, like `canAccessStateProvider` |
| `phoneValidationActionsProvider` | Lists the validation methods and the paired phones, and starts, answers or cancels a validation |
| `commandAvailabilityProvider` | Which commands the device accepts now (`SystemState.command_availability`), from the current connection only: null until reported on it, cleared on every transport or connection change and when the device goes quiet, never cached. Over MQTT it covers the basic commands |
| `vehicleHistoryProvider` | Recent values of the series the paired vehicle's tiles draw (charts, sparklines), sampled from live state only, in memory |
| `commandUiStateProvider` | `enabled`, `disabled` (greyed out) or `hidden` for one command, from the availability and the remembered unsupported commands |
| `unsupportedCommandsProvider` | The commands each vehicle reported `UNSUPPORTED`, saved in `SharedPreferences` |
| `savedLayoutsProvider` | The user's dashboard layouts, per vehicle and grid, saved in `SharedPreferences` |
| `dashboardLayoutProvider` | The layout a tier's grid shows on the current vehicle: the user's, cleaned up against the catalog, or the default |

`VehicleSnapshot` fields (`basicState`, `advancedState`) are typed as `GeneratedMessage`; the vehicle's catalog accessors cast them. They are decoded once per message and merged via `mergeFromMessage`.

Commands complete when a `CommandResponse` with the same `message_id` arrives (15 s timeout). Command IDs start at a random value below 2^32 on each launch; MQTT heartbeats use IDs from 2^32 up so a response can never match a heartbeat. `CarTransport.send` throws `CarTransportException` when it can't send (e.g. MQTT offline, or an advanced command over MQTT), so the UI shows the error at once instead of waiting for the timeout.

`debugOverrideBasicState()` (debug builds only) replaces the basic state locally; the E-GMP debug drawer uses it to exercise the UI and 3D animations.

### Vehicle control (CAN read-write)
The device only listens to the car until three things hold (firmware `docs/can.md`, "Read-write policy"): it has identified the car, the owner has approved control of that car, and, in development firmware builds, the developer write lock is unlocked (it locks again at every restart). The app reads why from `canAccessStateProvider` and changes it with `canAccessActionsProvider`, both over BLE only:

*   The dashboard's banner slot shows a banner when the car is identified but control isn't approved, or was approved for a different car, and opens the approval dialog. It comes after the platform-mismatch and bond-lost banners.
*   `showCanReadWriteApprovalDialog` shows the risks and only sends the approval once the owner ticks "I understand the risks". The approval belongs to the car the device is plugged into; the device keeps it across restarts and phone changes.
*   `CanAccessSection` shows the state and the reason in words (`canAccessSummary`), approving and withdrawing the approval, and the developer write lock switch when the firmware reports `dev_lock_available`. The settings screen shows it.

`canAccessStateProvider` listens to the transport itself rather than reading `VehicleSnapshot.system`: the snapshot is restored across transport switches and cached across restarts, so its `can_access` could show "Control enabled" for a device that has since restarted read-only. The device repeats the access state every few seconds, so a new connection gets it quickly.

While the device is read-only it refuses basic and advanced commands with a failed `CommandResponse` whose message gives the reason (e.g. "command rejected: the device is read-only: the developer write lock is locked"); the command's future fails with a `CommandRejectedException`, which carries the whole `CommandResponse` and reads as that message. Tiles send commands through `sendVehicleCommand` (`lib/widgets/vehicle_command_feedback.dart`), which shows the reason in a SnackBar, with a "Review" action opening the approval dialog when control still needs approving.

The device never sends the car's VIN or fingerprint, so the dialog can't name the car.

### Phone validation
Pairing doesn't prove a phone is the owner's, so the device only accepts vehicle commands from a phone validated in the car (firmware `docs/ble.md`, "Phone trust"). Over BLE, every command is reported unavailable until then, and the dashboard stays on the remote tier. `PhoneValidationScreen` is the flow (see [Other screens](ui-screens.md#phone-validation)), on top of:

*   `phoneAccessStateProvider` holds the phone's trust level, whether the car has a validated phone, and its session. It listens to the transport itself, like `canAccessStateProvider`, for the same reason: a cached "validated" must never show. Its fields merge as usual, except the session, which replaces the previous one. The device reports the session whole and leaves it out once the phone has none, and zero values (no attempts left, no time left) aren't on the wire, so merging would keep old values.
*   `phoneValidationActionsProvider` sends `ListPhoneValidationMethods`, `StartPhoneValidation`, `SubmitPhoneValidationCode`, `CancelPhoneValidation` and `ListPairedPhones` through `sendSystemCommand`, so they are refused over MQTT without sending anything. They return what `CommandResponse.system_result` carries; `ListPairedPhones` gives `PairedPhoneInfo`s, with each phone's trust and which one is this phone.
*   A refused command throws `CommandRejectedException`. `validationSession` is the session and its attempts left after a wrong code; `validationRefusal` is the reason for any other refusal, with the cooldown left. `needsValidation` is true for `COMMAND_STATUS_CODE_REJECTED_NOT_VALIDATED`: a vehicle command from a phone that isn't validated or, once a phone is validated for this car, the approval or removing a validated phone. `sendVehicleCommand` then says the phone needs validating in the car. Since such commands are greyed out, the app only gets this when its availability is out of date.
*   The limits (`[ble.phone_validation]` in `transport.toml`) are generated with the other constants as `kBlePhoneValidation*`, for the instructions. The session messages carry the time and attempts left.
*   `phoneValidationMethodText` maps each `method_id` to the app's text, with a generic text per kind for an id the app doesn't know.

### Command availability
The device decides which commands it accepts right now and reports it (firmware `docs/commands.md`, "Command availability"): `SystemState.command_availability`, over BLE and over MQTT (basic commands only), repeated every few seconds. The app greys out the tiles of commands the device doesn't accept, and the dashboard leaves out the tiles of commands reported `UNSUPPORTED` (not on this car; nothing sends that yet), so the tiles after them close the gap. They stay left out in every later connection (see below). A tap on a greyed-out tile (`CommandControl`) says why when the app knows: the device reports no reason, so it comes from the transport and the access states (`commandUnavailableReason`). The device rejects an unavailable command with `COMMAND_STATUS_CODE_REJECTED_UNAVAILABLE` even if the app sends it anyway, and `sendVehicleCommand` shows its reason.

*   Commands are identified by their field number in the vehicle's `BasicCommand` / `AdvancedCommand` oneof. Each vehicle keeps them in `lib/cars/<vehicle>/command_ids.dart`, read from the generated messages with `commandId` so they can't drift from the contracts. Every command tile's key comes from there; a new command is greyed out over BLE until the device lists it.
*   Like `canAccessStateProvider`, `commandAvailabilityProvider` listens to the transport itself and never reads the cached snapshot, so a cached "available" can't enable a button. It is cleared when the device goes quiet for `kStateLivenessTimeout` (30 s), the same time the vehicle state takes to go stale, over BLE and MQTT alike. Losing the connection clears it at once. What the device would reject is enforced on the device whatever the app shows.
*   `UNSUPPORTED` is about the car, so unlike the rest it is remembered per vehicle (`unsupportedCommandsProvider`), across connections and app runs: the tile stays out before the first report and while offline. This can only hide a command, never enable one. Only an `AVAILABLE` report takes a command back, because `UNAVAILABLE` is also what the device says over MQTT and to a phone that isn't validated.
*   Over BLE and MQTT a command is enabled only while the device says it accepts it, so the buttons are greyed out right after connecting until the first report. While MQTT commands are not authenticated the device reports every command unavailable over MQTT. The stub and HTTP debug transports may not report anything, so there the buttons stay enabled and the device rejects what it can't do.

### Dashboard (`lib/screens/dashboard/`)
`DashboardScreen` is the one screen for every vehicle. It reads the current vehicle's description and shows the layout from `dashboardLayoutProvider` (the user's, else `VehicleDefinition.defaultLayout`) for the tier from `dashboardTierProvider`: **remote** over MQTT and for a phone not reported as validated, **Bluetooth** for a validated phone over BLE or HTTP and for the stub. `dashboardTierFor` gives the link's own tier, which the connection pill and the settings sections follow. Gate on the transport type, never on the vehicle.

*   **Tiles:** `catalogGridItems` turns the layout into `TileGrid` items. Over MQTT advanced tiles are left out; a tile whose command is `hidden` is left out on both tiers.
*   **Saved layouts:** stored per vehicle and `DashboardGrid` under `PairedVehicleConfig.storageKey`, the vehicle's id. They hold only tile ids and sizes; `sanitizeLayout` drops what the catalog no longer has when reading, and tiles a newer app adds are left to "Add a tile".
*   **Editing:** each `DashboardGrid` declares its `TileGridEditing`. `DashboardScreen` swaps in the edit controls (`tile_editing.dart`) and turns each edit into a saved layout. `TileGrid` handles the drag for items with `TileDragHandlers`, and items without them stay after those that have them.
*   **Remote tier:** the hero (`VehicleDefinition.buildHero`) sits in a box between the header and the frosted tile layer. `MeasureSize` reports the header's and the layer's heights; the box takes what is left, down to `kHeroMinHeight`, after which the layer scrolls over the hero. It follows the layer's height frame by frame, so it moves with the grid's own resize animation. On wide screens (`kWideLayoutMinWidth`) the hero fills the left column and the tiles move to a side column.
*   **Bluetooth tier:** a slim header over a full-screen grid, eight columns on wide screens.
*   **Switching tier:** when the link or the phone's trust changes, the screen cross-fades straight to the other tier (instantly with reduced motion).
*   **Header** (`DashboardHeader`): the vehicle name (`VehicleNameButton`, which opens the vehicle switcher), the level rows (`VehicleDefinition.energy`), the connection pill and the settings button; on the remote tier also the speed while driving and the status line. The pill says Remote or Bluetooth while the state is live, otherwise "Offline · Updated …", and its dot spins while `pendingCommandControlsProvider` has a command in flight.
*   **Vehicle switcher** (`vehicle_switcher.dart`): a popover anchored to the name, listing `vehicleListProvider`. The current vehicle's line follows its live connection (`connectionLabel`, as the pill); the others show their `VehicleSummary`. Switching calls `pairedVehiclesProvider.notifier.switchTo()`, and the providers rebuild for the new vehicle (see "Several vehicles" under [UI architecture](#ui-architecture)). The Vehicles screen (`lib/screens/vehicles_screen.dart`) lists the same entries.
*   **Stale values:** `StaleValues` marks values from a past snapshot (state not live, or for an advanced tile, advanced state not live); `TileSurface` and the header dim them. The hero dims itself from the snapshot.
*   **Banners:** `DashboardBannerSlot` shows the most important of: platform mismatch, Bluetooth bond lost, control not approved.
*   **Pull to refresh** (`pullToRefresh()`) works anywhere on the page: the whole page scrolls, even where the header and the hero stay put.
*   **Settings button:** opens `SettingsScreen` (see [Settings](ui-screens.md#settings)). It completes with whether the user chose Edit dashboard, and the dashboard then enters edit mode. The sections the device has to answer for are gated by tier, so they are hidden over MQTT.
*   **System commands without an answer:** the device only answers a restart or a phone removal to refuse it, so these go through `sendUnansweredSystemCommand`, which completes once a refusal would have arrived rather than timing out.
*   **Debug drawer:** in debug builds, a long press on the vehicle name opens `VehicleDefinition.buildDebugDrawer()` (E-GMP has one).

## 3D viewer
E-GMP's hero (`Vehicle3DViewer`, returned by `buildHero`) renders the car with a Three.js viewer (`web_3d/`, bundled with Vite into `assets/web/` and shown in a `flutter_inappwebview`). The page is served from the APK by Android's `WebViewAssetLoader` (`https://appassets.androidplatform.net/assets/flutter_assets/...`), not a local HTTP server.

The widget takes the snapshot from the dashboard and reads no providers, as the [hero interface](ui-hero.md#interface-proposal) asks. Flutter only sends target state (`window.setVehicleState(...)`), and only when it changes. Fades, the power-flow pulse and hazard blinking are animated by the render loop in `app.js`. When the scene settles, the viewer saves a PNG snapshot (one per theme) to the app support directory. The snapshot is shown while the WebView boots and grayed out when the state is stale.

The runtime model is meshopt-compressed from an uncompressed export in `assets_src/`. See [`web_3d/README.md`](../web_3d/README.md).
