# UI mockups

Sources of the dashboard mockups described in [UI design](../../ui.md). Screenshots rendered from them are in [`../images`](../images).

The files are artboards for the Claude Design canvas (`*.dc.html`, with `canvas.json` as the canvas index). They are a design reference for the Flutter implementation, not shipped code, and nothing in the app builds or imports them.

## Files
| File | What it is |
|---|---|
| `Phone.dc.html` | The shared screen. All dashboard artboards import it with different options |
| `Main`, `RemoteDark`, `BleLight`, `BleDark`, `Driving`, `Offline`, `IceRemote`, `IceBle`, `Tablet`, `SkinBoxy`, `SkinRound` (`.dc.html`) | One-line artboards that import `Phone` with a set of options |
| `LevelIdeas`, `ControlIdeas` (`.dc.html`) | Static design explorations for the level indicator and the control buttons |
| `canvas.json` | Canvas index: artboard positions and order |

## Options of the shared screen
Set as attributes on the `dc-import` in an artboard (or in the component's Tweaks panel):

| Option | Values | Meaning |
|---|---|---|
| `vehicle` | `ev`, `ice` | Battery or fuel glyph, EV-only buttons and stats |
| `tier` | `remote`, `ble` | Remote shows the basics. BLE adds live data and advanced controls |
| `theme` | `light`, `dark` | Brightness |
| `layout` | `phone`, `wide` | Controls over the hero, or a side column |
| `buttons` | `titled`, `icon` | Button style |
| `skin` | `default`, `boxy`, `round` | Shape and accent tokens (see [Theming](../../ui-theming.md)) |
| `driving` | `true`, `false` | Road scene, speed and Driving status |
| `connected` | `true`, `false` | Connection pill vs the Offline pill |

All values (battery level, range, temperatures, charging, stats) are made up. The icons, the car and the road are placeholder drawings. Taps change local mock state only.

## Viewing and re-rendering
*   The screenshots in [`../images`](../images) are the quickest way to see the design.
*   To open or edit the mockups, import the files as artboards into a Claude Design canvas.
*   Rendering them outside the canvas needs the canvas runtime (`support.js`, which the files load). It is not included in the repo.

## Keeping them in sync
The mockups describe the design, so they should not be edited to follow the app. When the design changes, change the mockups and [`ui.md`](../../ui.md) together, and re-render the screenshots.
