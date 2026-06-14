# Open Car App

Flutter mobile app for interacting with an ESP32-based car controller over BLE (local) and MQTT (remote).

## Prerequisites

Use the provided dev container — it includes Flutter, the Android SDK, `protoc`, and `protoc-gen-dart` pre-installed.

If you are **not** using the dev container, run this once after cloning to prevent Flutter from listing Linux as a target device:

```sh
flutter config --no-enable-linux-desktop
```

This setting is user-level (`~/.config/flutter/settings`) — there is no project-level equivalent. The dev container handles it automatically via `postCreateCommand`.

### Native Windows Setup (Optional)
While the dev container is recommended, you can set up a local Windows environment directly:
1. **Android Studio**: Download and install [Android Studio](https://developer.android.com/studio).
2. **Android SDK**: Open Android Studio's SDK Manager and install:
   - Android SDK Platform 36
   - Android SDK Build-Tools 36.0.0
   - Android SDK Command-line Tools (latest)
3. **Flutter SDK**: Download Flutter SDK version `3.41.6` from [flutter.dev](https://docs.flutter.dev/release/archive) or clone it via git. Extract it (e.g., to `C:\flutter`) and add `C:\flutter\bin` to your system `PATH`.
4. **Java JDK**: Java 21 is required. If Android Studio's bundled JDK is not Java 21, you may need to install OpenJDK 21 manually.
5. **Protoc Plugin**: Install the Dart protocol buffers plugin globally:
   ```powershell
   dart pub global activate protoc_plugin 21.1.2
   ```
   Add your pub-cache bin to your system `PATH` if it isn't already (e.g. `C:\Users\<user>\AppData\Local\Pub\Cache\bin`).

## Running on Android (wireless debugging)

The dev container has no USB passthrough, so use ADB over Wi-Fi.

1. On the phone, enable **Developer options → Wireless debugging** and tap **Pair device with pairing code**.
2. In the terminal, pair once using the pairing port and code shown on the phone:
   ```sh
   adb pair <phone-ip>:<pairing-port>
   ```
3. Connect using the main wireless debugging port (different from the pairing port, also shown on the phone):
   ```sh
   adb connect <phone-ip>:<port>
   ```
4. Verify the device is listed:
   ```sh
   flutter devices
   ```
5. Run the app:
   ```sh
   flutter run
   ```

The pairing step (steps 1–2) is only needed once per network session. The `adb connect` (step 3) must be repeated each time the dev container restarts.

## Code generation

This project generates Dart code from the `contracts/` git submodule (protobuf schemas and TOML metadata). Generated files are committed, so a normal `flutter build` always works without running codegen first.

You need to regenerate when:
- The `contracts` submodule is updated (`git submodule update`)
- You add a new vehicle platform under `contracts/opencar/cars/`

Run:
```sh
dart run build_runner build --delete-conflicting-outputs
```

This produces:
- `lib/generated/` — Dart classes for all `.proto` files (`AppToDevice`, `DeviceToApp`, `BasicState`, etc.)
- `lib/cars/<vehicle>/constants.g.dart` — typed constants sourced from each vehicle's `meta.toml` and the shared `transport.toml` (platform ID, BLE UUIDs, MQTT topic templates)

Both are driven by a custom `build_runner` builder in `tool/builders/`. Unlike Rust's `build.rs`, Dart has no compiler-integrated codegen hook, so this step is manual. There is no need to run it on every build — only when the contracts change.

## Architecture

Communication between the app and the car controller uses a common protobuf envelope pattern:
- `AppToDevice` / `DeviceToApp` — core transport envelope (platform-agnostic)
- Vehicle-specific state and commands are serialized to `bytes` fields inside the envelope and decoded using the `platform_id` CRC32 from `meta.toml`
- The same wire format is used over both BLE and MQTT
