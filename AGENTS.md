# Agent rules

Rules for AI agents working in this repo. Project knowledge (architecture, BLE and pairing, code generation, setup, releases) lives in `docs/` and `README.md`; read the relevant page before changing an area.

## Rules

### Build & checks
*   All tooling (Flutter, Android SDK, `protoc`, `protoc-gen-dart`) is pre-installed in the dev container; don't try to install tools manually.
*   Before finishing a change, run what CI runs: `dart format` on non-generated Dart files, `flutter analyze --fatal-infos` and `flutter test`.
*   If you can't run something (e.g. a device build), say so rather than claiming it works.

### Generated code
*   Generated files (`lib/generated/**`, `*.g.dart`) are committed but never hand-edited. Change the source (`contracts/`, `config.toml.example`) and re-run `dart run build_runner build --delete-conflicting-outputs`.
*   Never copy-paste values from `contracts/` TOML (UUIDs, platform IDs, topics); import them from the generated `constants.g.dart`.
*   `contracts/` is a git submodule shared with the firmware repo. Don't edit it from here unless explicitly asked.

### App conventions
*   Merge incoming state with `mergeFromMessage`; never replace the whole state (fields are `optional`).
*   Gate BLE-only features (advanced state/commands, system commands) on the transport type; MQTT only carries basic state/commands.
*   Never hardcode `source_device_id`; use `bleSourceDeviceIdProvider`.
*   Don't call `createBond()`; bonding is driven by the write-probe in the pairing wizard.
*   Keep debug-only paths (HTTP transport) behind `kDebugMode`.

### Git & files
*   `config.toml` is gitignored and holds credentials. Never commit it or print its contents; edit `config.toml.example` for defaults.
*   Commits and PR titles use conventional-commit style (`feat:`, `fix:`, `chore:`); CI validates PR titles and `semantic-release` derives versions from them.

### Keeping docs current
*   When a change alters behaviour described in `docs/` or the README, update that page in the same change.
*   Put new project knowledge in the matching `docs/` page (or a new page there), not in this file. This file only gets rules about how to work.
*   Don't record volatile facts (file lists, counts, line numbers) in docs; they go stale.
