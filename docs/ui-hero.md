# 3D hero

The vehicle picture at the centre of the [dashboard](ui.md). It is a separate widget with a small interface, so the dashboard can be built and tested before the 3D implementation is chosen. This page records what the hero must do, what is known about the options, and how to decide.

> **Status:** the current dashboard renders the car with a Three.js viewer in a WebView (see [Architecture](architecture.md#3d-viewer)). Replacing the WebView is planned; the options below are not yet evaluated on a device.

## What the hero does
*   **Camera is never user-controlled.** No orbit, pan or zoom. State and animation move it.
*   **Orthographic camera**, looking at the car from the front-driver side and above by default.
*   **State-driven camera moves.** The camera swings to a different view when the state calls for it. Today: it flips to the rear when the charge port is open, because on the EV6 the port is at the rear passenger side. Platforms define their own views.
*   **State-driven parts.** Doors, windows, frunk and trunk, lights and hazards, the charge port and cable, and a charging glow animate to match the state.
*   **Driving scene.** When driving, the car sits on a road that advances (the dashed lane line scrolls) at a rate tied to the speed. The speed itself is drawn by the header, not the hero.
*   **Transparent background.** The hero draws over the page colour, with Flutter UI above it (the header and the frosted controls layer).
*   **Fits its box.** The dashboard gives the hero a box. The car is centred and scaled to fit the box's width and height, never clipped.
*   **Plain fallback.** While the viewer boots, and when it fails, a still image of the car is shown. The current viewer already caches a snapshot per theme; keep that idea.
*   **Stale state.** A hero for stale data looks stale (dimmed), like the rest of the screen.

## Interface (proposal)
The hero is a widget that takes state and a box, and nothing else:

| Input | Notes |
|---|---|
| Box size | Given by the dashboard's layout; changes while controls unfold, animated |
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

This table is a snapshot of what was known at design time. Check current versions before deciding.

## Spike
Decide from a device test, not from documentation. One minimal Flutter app per candidate, loading the current model (first the meshopt-compressed one, then an uncompressed one if that fails), and checking:

1.  An orthographic camera at the default angle.
2.  A scripted camera move to the rear and back.
3.  Playing named part animations: doors, hood, trunk, charge port.
4.  Emissive lights, and blinking hazards.
5.  Recolouring the paint material.
6.  A transparent background, with Flutter widgets drawn over and under it.
7.  Resizing the viewer's box while it animates (the dashboard does this).
8.  Frame rate, memory and start-up time on a real mid-range phone, and what happens on pause and resume.

The simulator cannot answer the last item, so this has to run on the maintainer's phone. Pick the candidate that passes 1–7 with acceptable numbers for 8. If none does, fix the WebView approach instead of living with it.

## Model
The current model is a modified copy of a high-poly model from the web (see `assets_src/README.md` for the source and the licence terms). Its parts are separated for animation, but it is not otherwise optimised for mobile. Optimising it (triangle budget, merging static parts, texture sizes, draw calls) is separate work, planned after the viewer decision. Keep the node, material and animation names stable across any re-export, because the viewer looks them up by name. Update the attributions in `lib/cars/<platform>/licenses.dart` whenever the model changes.
