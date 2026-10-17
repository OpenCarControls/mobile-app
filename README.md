# Open Car App

Flutter mobile app for interacting with an ESP32-based car controller over BLE (local) and MQTT (remote). Supports the Kia/Hyundai E-GMP platform and a virtual car for UI testing without hardware.

## Getting started

1.  Open the repo in the provided dev container (Flutter, Android SDK, `protoc` and `protoc-gen-dart` are pre-installed). For a native Windows setup, see [Development setup](docs/development-setup.md).
2.  Fetch the shared contracts submodule: `git submodule update --init`.
3.  Create your local config: `cp config.toml.example config.toml` and fill in the MQTT credentials (gitignored).
4.  Connect a phone over wireless debugging (steps in [Development setup](docs/development-setup.md#running-on-android-wireless-debugging)) and run:

    ```sh
    flutter pub get
    flutter run
    ```

## Code generation

Dart code is generated from the `contracts/` submodule and `config.toml`. Generated files are committed, so builds work without it; re-run it when the contracts or config change:

```sh
dart run build_runner build
```

See [Code generation](docs/code-generation.md) for what gets generated.

## Checks

```sh
flutter analyze --fatal-infos
flutter test
```

## Architecture

The app and the controller share a protobuf envelope (`AppToDevice` / `DeviceToApp`) carrying vehicle-specific bytes, decoded by `platform_id`; the same wire format runs over BLE and MQTT. Each supported vehicle is a `VehicleDefinition` under `lib/cars/<vehicle>/`.

*   [Architecture](docs/architecture.md) — vehicles, transports, providers, UI
*   [BLE & pairing](docs/ble.md)
*   [Code generation](docs/code-generation.md)
*   [Development setup](docs/development-setup.md)
*   [CI & releases](docs/releases.md)
*   [3D viewer](web_3d/README.md)

## Project structure

```
.
├── contracts/        # git submodule: protobuf + TOML metadata shared with the firmware
├── lib/
│   ├── cars/         # one folder per supported vehicle
│   ├── config/       # app + generated MQTT config, device identity
│   ├── generated/    # committed generated protobuf classes
│   ├── models/       # VehicleDefinition
│   ├── providers/    # Riverpod providers
│   ├── screens/      # pairing wizard
│   └── transport/    # BLE, MQTT, HTTP (debug) transports
├── tool/builders/    # build_runner codegen package
├── web_3d/           # Three.js 3D car viewer (bundled into assets/web/)
├── assets_src/       # source 3D models
├── docs/             # project documentation
└── AGENTS.md         # rules for AI agents (CLAUDE.md imports it)
```

## License

This project is licensed under the terms of the [LICENSE](LICENSE) file.
