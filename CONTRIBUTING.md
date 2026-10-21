# Contributing to Open Car App

Thanks for your interest! This project is under construction and talks to a controller that drives real vehicle hardware, so contributions are reviewed carefully. Please read the warning in the [README](README.md) first.

## Before you start

*   **Open an issue first** for anything beyond a small fix, so we can agree on the approach before you spend time on it.
*   Supporting a new vehicle? Say which one and whether you have access to the car. Vehicle support also needs matching changes in the [`contracts`](https://github.com/OpenCarControls/contracts) and [`firmware`](https://github.com/OpenCarControls/firmware) repos.
*   Report security problems privately, as described in [SECURITY.md](SECURITY.md).

## Setup

Use the dev container (Flutter, Android SDK, `protoc` and `protoc-gen-dart` are pre-installed), or follow [Development setup](docs/development-setup.md) for Windows. Then fetch the submodule, copy `config.toml.example` to `config.toml`, and run `dart run build_runner build`. See the [README](README.md) and [`docs/`](docs/).

## Before opening a pull request

Run what CI runs:

```sh
dart format <changed non-generated files>
flutter analyze --fatal-infos
flutter test
```

*   Generated files (`lib/generated/**`, `*.g.dart`) are gitignored and never hand-edited. Change the source and re-run `dart run build_runner build`.
*   Never copy values (UUIDs, platform IDs, topics) from `contracts/`; import them from the generated `constants.g.dart`.
*   If you could not run something (for example a device build), say so in the PR.
*   Update the matching page in `docs/` (or the README) when you change documented behaviour.
*   Never commit `config.toml` (it holds credentials).

## Conventions worth knowing

*   Merge incoming state with `mergeFromMessage`; never replace the whole state.
*   Gate BLE-only features on the transport type; MQTT only carries basic state and commands.
*   Never hardcode `source_device_id`; use `bleSourceDeviceIdProvider`.
*   Don't call `createBond()`; bonding is driven by the write-probe in the pairing wizard.
*   Keep debug-only code (such as the HTTP transport) behind `kDebugMode`.

More detail is in [`docs/architecture.md`](docs/architecture.md) and [`docs/ble.md`](docs/ble.md).

## Changes to the wire format

Messages live in the shared `contracts/` submodule, which has append-only rules. Open the contracts PR first, then bump the submodule pin here in its own commit.

## Pull requests

*   Keep them small and focused; one topic per PR.
*   The PR title must use conventional-commit style (`feat:`, `fix:`, `docs:`, `chore:`). CI validates it, and `semantic-release` derives versions from it.
*   Fill in the PR template, including how you tested and whether a real vehicle or controller was involved.
*   AI-assisted contributions are fine, but you must understand and be able to explain every line you submit.
*   CI runs on your first PR only after a maintainer approves it.

By contributing you agree that your work is released under the project's [LICENSE](LICENSE).
