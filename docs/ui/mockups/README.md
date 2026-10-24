# UI mockups

Sources of the mockups described in [UI design](../../ui.md), [Other screens](../../ui-screens.md) and [Theming & skins](../../ui-theming.md). Screenshots rendered from them are in [`../images`](../images).

The files are artboards for the Claude Design canvas (`*.dc.html`, with `canvas.json` as the canvas index). They are a design reference for the Flutter implementation, not shipped code, and nothing in the app builds or imports them.

## Files
| File | What it is |
|---|---|
| `Phone.dc.html` | The shared dashboard: the tile grid, header, climate tile, edit mode, hero placeholder and skins. Most dashboard artboards import it with different options |
| `Main`, `RemoteDark`, `Driving`, `Offline`, `IceRemote`, `BleLight`, `BleDark`, `IceBle`, `Tablet`, `SkinBoxy`, `SkinRound` (`.dc.html`) | One-line artboards that import `Phone` with a set of options |
| `Wizard.dc.html` | The setup wizard: prompt, scanning, found, error, and the "add a vehicle" variant |
| `Settings.dc.html` | The settings screen (a component), imported by `SettingsBle` and `SettingsRemote` |
| `Activity.dc.html` | The connection activity popover over the Bluetooth dashboard |
| `Switcher.dc.html` | The vehicle switcher popover over the remote dashboard |
| `Vehicles.dc.html` | The Vehicles screen and the unpair dialog, imported by `VehiclesList` and `VehiclesUnpair` |
| `LevelIdeas`, `ControlIdeas` (`.dc.html`) | Static design explorations for the level indicator and the control buttons |
| `canvas.json` | Canvas index: artboard positions and order |

## Options of the dashboard (`Phone`)
Set as attributes on the `dc-import` in an artboard (or in the component's Tweaks panel):

| Option | Values | Meaning |
|---|---|---|
| `vehicle` | `ev`, `ice` | Battery or fuel, EV-only tiles and stats |
| `tier` | `remote`, `ble` | Remote: hero behind a few basic tiles. BLE: the tile dashboard, no hero |
| `theme` | `light`, `dark` | Brightness |
| `layout` | `phone`, `wide` | Phone, or the tablet layout (side column on remote, eight columns on BLE) |
| `buttons` | `titled`, `icon` | Command tile style |
| `skin` | `default`, `boxy`, `round` | Shape and accent tokens (see [Theming](../../ui-theming.md)) |
| `driving` | `true`, `false` | Road scene and speed (remote), Speed tile value (BLE) |
| `connected` | `true`, `false` | Connection pill vs the Offline pill |

`Settings` takes `tier`, `theme` and `skin`. `Vehicles` takes `theme` and `dialog` (shows the unpair confirmation).

All values (levels, ranges, temperatures, charging, stats, vehicles, log entries) are made up. The icons, the car and the road are placeholder drawings. Taps change local mock state only: tiles pend and update, the climate unfolds, and edit mode can resize and remove tiles, but dragging is not implemented.

## Viewing and re-rendering
*   The screenshots in [`../images`](../images) are the quickest way to see the design.
*   To open or edit the mockups, import the files as artboards into a Claude Design canvas.
*   Rendering them outside the canvas needs the canvas runtime (`support.js`, which the files load). It is not included in the repo.

## Keeping them in sync
The mockups describe the design, so they should not be edited to follow the app. When the design changes, change the mockups and the docs together, and re-render the screenshots.
