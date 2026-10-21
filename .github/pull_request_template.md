## What and why

<!-- What does this change do, and why? Link the issue it addresses. Add screenshots for UI changes. -->

## How it was tested

<!-- Unit tests, emulator, real device, real controller or vehicle? Say what you could NOT run (e.g. a device build). -->

## Checklist

- [ ] PR title uses conventional-commit style (`feat:`, `fix:`, `docs:`, `chore:`); CI validates it
- [ ] `dart format`, `flutter analyze --fatal-infos` and `flutter test` pass
- [ ] Docs (`docs/` or README) updated if behaviour changed
- [ ] No `config.toml` or credentials committed; generated files not hand-edited
- [ ] If the wire format changed: the contracts PR is linked and the submodule bump is its own commit

## Safety

- [ ] This change does **not** touch BLE pairing/bonding or how commands are sent to the vehicle
- [ ] It does (explain below)

<!-- Explain any safety-sensitive change here. -->
