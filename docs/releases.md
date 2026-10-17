# CI & releases

## CI (`.github/workflows/ci.yml`)
Installs `protoc`, runs `flutter pub get` and codegen, then checks formatting (`dart format`, excluding `*.g.dart` and `lib/generated/`), `flutter analyze --fatal-infos` and `flutter test`. PR titles are validated as semantic/conventional-commit titles (`pr-lint.yml`, `semantic-pr.yml`).

## Releases
Releases are automated with `semantic-release` (`.releaserc.json`) from the `release.yml` workflow, which runs after CI succeeds on `main` (or manually via `workflow_dispatch`).

*   Version bumps are derived from conventional commits (`feat:` → minor, `fix:` → patch, breaking → major).
*   Tags use the format `v<version>`.
*   The release builds `flutter build apk --release` and attaches `open-car-app-v<version>.apk` to the GitHub Release.
