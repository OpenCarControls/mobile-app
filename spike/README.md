# 3D hero renderer spike (#75)

Throwaway apps for choosing the hero renderer (see `docs/ui-hero.md`, "Spike"). This folder lives on the `spike/75-hero-renderer` branch only; the results go into `docs/ui-hero.md`.

| Folder | What it is |
|---|---|
| `hero_harness/` | Shared screens, state and measurements. Every candidate app is `SpikeApp(builder: ...)` plus one renderer widget. |
| `webview_spike/` | Baseline: the shipped Three.js bundle (`assets/web`) in the same WebView setup as the app, minus the snapshot cache. |
| `thermion_spike/` | Thermion (Filament) candidate. |
| `flutter_scene_spike/` | flutter_scene (Flutter GPU) candidate. Its build hook converts the models to `.fsceneb`; they are symlinked under its own `assets/models/` and named explicitly in `hook/build.dart` (discovery skips symlinks). |

Both models come from the app through symlinks in `hero_harness/assets/models/`: `ev6_meshopt.glb` (shipped, meshopt-compressed) and `ev6_raw.glb` (`assets_src`, uncompressed).

## Screens
*   **Checklist**: the hero in a box, with toggles for each checklist item. Camera (rear view), parts (doors, hood, trunk, port, windows in steps), lights, hazards, cables, power flow, paint, Flutter content under and over the view, box resizing (manual or a loop), theme, model choice and remount (cold start). **Run demo** steps through all of it and logs a metrics summary. Renderer-specific sliders are under **Tuning**.
*   **Grid**: 0–4 small viewers among plain tiles in a scrolling grid. The auto-scroll button scrolls down and up twice and logs a metrics summary.
*   **Log**: the event log, also printed to logcat as `[spike] ...`.

The badge at the top right shows Flutter frames per second, raster time (average/worst over 2 s), over-budget frames since the last reset, and process RSS. An idle screen shows 0 fps: Flutter produces no frames when nothing changes. GPU memory may not appear in RSS; use `adb shell dumpsys meminfo <package>`.

## Build and run
From an app folder, after `flutter pub get`, build a release APK for arm64 (Thermion ships arm64 only on Android):

```bash
cd android && ./gradlew --no-daemon -Ptarget-platform=android-arm64 -Ptree-shake-icons=false app:assembleRelease; ./gradlew --stop
adb install -r build/app/outputs/flutter-apk/app-release.apk   # from the app folder
adb logcat -s flutter
```

`android/gradle.properties` caps the Gradle heap at 4 GB; the default 8 GB has frozen the dev container before.
