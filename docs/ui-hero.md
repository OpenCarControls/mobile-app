# 3D hero

The vehicle picture on the [dashboard](ui.md). It is a separate widget with a small interface, so the dashboard can be built and tested before the 3D implementation is chosen. This page records what the hero must do, what is known about the options, and how to decide.

## Where it appears
*   **Remote tier:** behind the tile grid, in a box between the header and the tiles. The dashboard gives it that box and resizes it as tiles are added (see [the hero box](ui.md#remote-tier)).
*   **Bluetooth tier:** not shown by default, since you are in the car and the screen space is better used by tiles. It can come back as a **Car view** tile (2×2 or 4×2) from the "Add a tile" list. The tile gives the hero a box of the tile's size.
*   It is the same widget in both places. It must work at any box size, not only the full-screen one, and should be cheap enough to run inside a scrolling grid.

> **Status:** `VehicleDefinition.buildHero` is the interface. E-GMP's hero renders with Thermion, as the [spike](#spike) decided (see [Architecture](architecture.md#3d-hero)); it takes the snapshot and the box from the dashboard, and the Car view tile uses the same widget. The virtual car uses the placeholder (`HeroPlaceholder`). Not built yet: the driving scene (road), and the skin accent on the charge glow and cable.

## What the hero does
*   **Camera is never user-controlled.** No orbit, pan or zoom. State and animation move it.
*   **Orthographic camera**, looking at the car from the front-driver side and above by default.
*   **State-driven camera moves.** The camera swings to a different view when the state calls for it. Today: it flips to the rear when the charge port is open, because on the EV6 the port is at the rear passenger side. Platforms define their own views.
*   **State-driven parts.** Doors, windows, frunk and trunk, lights and hazards, the charge port and cable, and a charging glow animate to match the state.
*   **Driving scene.** When driving, the car sits on a road that advances (the dashed lane line scrolls) at a rate tied to the speed. The speed itself is drawn by the header (remote tier) or a Speed tile (Bluetooth tier), not the hero.
*   **Transparent background.** The hero draws over the page colour (or a tile's surface), with Flutter UI above it (the header and the frosted tile layer).
*   **Fits its box.** The dashboard gives the hero a box. The car is centred and scaled to fit the box's width and height, never clipped.
*   **Plain fallback.** When the renderer fails, the placeholder is shown. While it boots, the box stays empty and the car fades in once drawn. A cached still was tried with Thermion (#76) and dropped: the engine starts fast enough that the still added nothing, and the switch from the still to the live view showed blank or black frames.
*   **Stale state.** A hero for stale data looks stale (dimmed), like the rest of the screen.

## Interface (proposal)
The hero is a widget that takes state and a box, and nothing else:

| Input | Notes |
|---|---|
| Box size | Given by the dashboard (remote tier) or by the Car view tile; changes while tiles unfold or are added, animated |
| Brightness | Light or dark |
| Skin accent | For the charge glow and cable |
| Vehicle snapshot (typed state) | Doors, windows, trunk and frunk, lights, hazards, charge port state, charge power, driving and speed, plus the advanced state when live |
| Reduced motion | Disable the camera glide, the road scroll and pulsing |
| Stale | Dim the car |

It reports nothing back. It must not send commands or read providers directly (the dashboard passes state in), so a placeholder can stand in for it in tests.

The platform provides its hero (model, named parts, camera views). A platform without a 3D model can supply a still image with a few overlays. The dashboard does not care which.

### Placeholder
The mockups use a flat top-down drawing as a placeholder. A placeholder widget is the first deliverable: it lets the dashboard, layout, scrolling and box-resize behaviour be built and tested without any 3D code.

## Options
Pre-rendered image layers were considered and dropped: the camera moves between views, and every view would need its own full set of part layers, which does not scale.

| Option | Notes | Open risks |
|---|---|---|
| Keep Three.js in the WebView | Works today. Its drawbacks are the WebView itself ("weird sometimes"), the layering of Flutter UI over a platform view, and the snapshot workaround. | The reason for replacing it |
| [Thermion](https://pub.dev/packages/thermion_dart) (native Filament) | The most mature Flutter-native option found. Loads glTF/GLB and plays skeletal and morph animations. Android arm64 only, needs Flutter's native-assets setup, and is a third-party dependency to maintain. | Orthographic camera, named-part control, emissive materials, transparent background under Flutter UI, meshopt-compressed models |
| [flutter_scene](https://pub.dev/packages/flutter_scene) (Flutter GPU) | The most Flutter-native option: glTF, skeletal animation, PBR. | Pre-1.0 and built on Flutter GPU, which had not shipped as stable when checked. Earlier versions needed a master-channel Flutter. |

This table is a snapshot of what was known at design time. The [spike results](#results) below replace its open risks.

## Spike
Decide from a device test, not from documentation. One minimal Flutter app per candidate, loading the current model (first the meshopt-compressed one, then an uncompressed one if that fails), and checking:

1.  An orthographic camera at the default angle.
2.  A scripted camera move to the rear and back.
3.  Playing named part animations: doors, hood, trunk, charge port.
4.  Emissive lights, and blinking hazards.
5.  Recolouring the paint material.
6.  A transparent background, with Flutter widgets drawn over and under it.
7.  Resizing the viewer's box while it animates (the dashboard does this).
8.  Running small inside a scrolling grid, as a Car view tile, without making the scroll janky.
9.  Frame rate, memory and start-up time on a real mid-range phone, and what happens on pause and resume.

The simulator cannot answer the last item, so this has to run on the maintainer's phone. Pick the candidate that passes 1–8 with acceptable numbers for 9. If none does, fix the WebView approach instead of living with it.

### Results
Run in November 2026 (#75) on a Pixel 9 Pro Fold (120 Hz) in release builds, with Thermion 0.7.0, flutter_scene 0.24.3 and Flutter 3.50. Each candidate was a small app around the same test harness: the checklist above as toggles, a scripted demo, a scrolling grid of small viewers and a frame/memory readout. The apps are kept on the unmerged `spike/75-hero-renderer` branch.

| | WebView (Three.js) | Thermion | flutter_scene |
|---|---|---|---|
| Model | Meshopt | Meshopt | Raw only: the build-time import breaks the meshopt model (doors, hood, wheels missing) |
| 1–6 | Pass | Pass, with workarounds (below) | Pass |
| 7. Resize while animating | Not checked | Pass with a grow-only texture; Thermion's own resize stretches, then flashes black | Reframes cleanly, but memory grew from 0.6 to over 1.5 GB during a resize loop |
| 8. Grid, 4 viewers, auto-scroll | 117 fps, but **tiles scrolled out of view stop rendering** | 113 fps, 5 slow frames of 1363 | 121 fps, 0 slow frames of 1429 |
| Cold start to ready | 0.8 s | 0.36 s | 0.45 s (5.5 s with the runtime glTF importer, which also blocks the UI thread) |
| Memory (PSS, checklist screen) | ~725 MB, including the 220 MB Chromium renderer process | ~440 MB | Not measured the same way (~600 MB process RSS) |
| Flutter raster time in the demo | Not comparable (the WebView draws in its own process) | 7.7 ms average | 3.6 ms average |
| Pause and resume | Pass | Pass | Not checked |

The lights were not judged on looks: they already look wrong with the WebView, which points at the model's light materials rather than the renderers (see [Model](#model)). The checks only confirmed that the right materials change and the hazards blink on time.

### Decision
**Thermion.** It passes every item with the compressed model and the best memory figure, and its problems all have working fixes. flutter_scene has the better design: it renders inside Flutter's frame, so idling, frame-rate caps and resizing come for free, and its frame times were the best. But it needs two bugs fixed or worked around (the meshopt import and memory growth on resize) and builds on Flutter GPU, which is still experimental and opt-in. Revisit it when Flutter GPU is stable and those are fixed.

### Notes for the Thermion hero
What the spike needed beyond the plain API, to carry into #76:
*   **Material lookup.** Thermion has no lookup by material name. Map names to (node, primitive index) by reading the GLB's JSON chunk, then fetch with `FilamentApp.getMaterialInstanceAt(entity, primitive)`. `ThermionAsset.getMaterialInstanceAt` ignores its index and always returns primitive 0 (0.7.0). Glass and lights share primitives with other parts on this model, so the wrong index recolours the windows.
*   **Unnamed mesh nodes.** In the meshopt model, mesh nodes are unnamed children of the named nodes, and Thermion names their entities after the mesh. Resolve parts through the named parent.
*   **Camera.** `ThermionWidget` resets the camera to a perspective lens whenever it (re)creates its texture. Use `ThermionWidgetInternal` with your own `onTexturePreparing` that sets the orthographic projection.
*   **Resizing.** The texture follows the box with a 100 ms debounce, stretching the old frame and then showing a black frame. Allocate the texture at the hero's largest size, let the box crop it (centred), and change only the projection as the box moves.
*   **First texture.** While the first texture is being allocated, every rebuild of `ThermionWidgetInternal` schedules another allocation, which swaps in a new, black texture 100 ms later (0.7.0). Create the widget once and pass the same instance on every build, so its parent never rebuilds it.
*   **Showing the view.** A texture is black until the engine has drawn into it, and Thermion has no "frame drawn" signal for app code. Keep the view mounted but hidden, and fade it in shortly after the first state is pushed. Fading the view (rather than something over it) keeps its first frames on screen nearly invisible.
*   **Power-flow scroll.** The ubershader multiplies `vec3(uv, 1) * emissiveUvMatrix` (a row vector), so the U offset goes in the third row of the matrix.
*   **Frame loop.** Animate from Flutter (a `Ticker`), setting animation times with `setGltfAnimationTime`, which is a job-thread round trip. Queue a frame's calls and await them together, and carry the time of skipped ticks into the next one.
*   **Idle.** Pause rendering (`setRendering(false)`) once nothing moves. Waking costs a short ramp-up, which is acceptable. While only the power flow or the hazard blink is moving, drop the frame rate (`setTargetFramerate`, 30 fps tested). Thermion's scheduler keeps ticking at 60 fps even while rendering is paused, so throttle it when idle too.
*   **Build.** The plugin compiles against Android SDK 33, below what Flutter 3.50's AndroidX libraries need; raise its `compileSdk` from the app's Gradle file. Native libraries are downloaded at build time, for arm64 only.
*   **Cables.** Filament cannot fade an opaque material, so the cables switch on and off through visibility layers where the WebView fades them.
*   **Exposure.** Light and emissive intensities are in Filament's physical units; the Three.js values do not carry over and need tuning against the model.

## Model
The current model is a modified copy of a high-poly model from the web (see `assets_src/README.md` for the source and the licence terms). Its parts are separated for animation, but it is not otherwise optimised for mobile. Optimising it (triangle budget, merging static parts, texture sizes, draw calls) is separate work, planned after the viewer decision. The light materials need fixing in that work too: they already look wrong with the WebView. Keep the node, material and animation names stable across any re-export, because the viewer looks them up by name. Update the attributions in `lib/cars/<platform>/licenses.dart` whenever the model changes.
