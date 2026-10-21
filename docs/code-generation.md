# Code generation

The app generates Dart code from the `contracts/` git submodule (protobuf schemas and TOML metadata) and from `config.toml`. Generated files are **gitignored**, so run codegen after cloning and before building; CI runs it before every build.

```sh
dart run build_runner build
```

Run it after cloning, and re-run it when:
*   the `contracts` submodule is updated (`git submodule update`),
*   you add a new vehicle platform under `contracts/opencar/cars/`,
*   `config.toml` (or `config.toml.example`) changes.

It does not need to run on every build, only when its inputs change. Unlike Rust's `build.rs`, Dart has no compiler-integrated codegen hook, so this step is manual. The builders live in `tool/builders/` (a `build_runner` package wired up by `build.yaml`).

| Source | Output | Builder |
|---|---|---|
| `contracts/**/*.proto` | `lib/generated/**/*.pb.dart` | `ProtoBuilder` |
| `contracts/opencar/cars/*/v1/meta.toml` + `transport.toml` | `lib/cars/<vehicle>/constants.g.dart` | `ConstantsBuilder` |
| `config.toml.example` (+ optional `config.toml`) | `lib/config/mqtt_broker_config.g.dart` | `MqttConfigBuilder` |

**`constants.g.dart`** exposes: `kPlatformId` (CRC32), `kPlatformName`, `kCanBusCount`, BLE UUIDs, MQTT topic templates, `kBlePairingWindowSeconds`, `kBleScanTimeoutSeconds`, and the BLE size and chunking constants (`kBleAttMtu`, `kBleMaxChunkBytes`, `kBleMaxMessageBytes`, `kBleChunk*`, `kBleMaxChunks`, `kBleMinAttMtu`, `kBleReassemblyTimeoutMs`). Never copy-paste TOML values — always import from the generated file.

**`mqtt_broker_config.g.dart`** exposes: `kMqttBrokerHost/Port`, `kMqttUsername/Password`, `kMqttClientId`, `kDebugServerHost/Port`, `kDebugServerPollingIntervalMs`.

## Local config
For local development: `cp config.toml.example config.toml`, then fill in credentials. `config.toml` is gitignored and must never be committed; `config.toml.example` holds the committed CI defaults.
