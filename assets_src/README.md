# Source Assets (assets_src)

This directory contains raw design assets, 3D source files (such as `.blend` Blender files), high-resolution textures, and workspace files.

## Guidelines

1. **Keep raw sources here**: Do **not** place `.blend` or raw project files in `assets/`. The `assets/` folder is packaged directly into the compiled Flutter application, whereas this `assets_src/` folder is ignored by Flutter.
2. **Export runtime assets**: Export final production-ready assets (e.g., `.png`/`.jpg` for compressed images) to the appropriate subfolder in `assets/` (e.g., `assets/cars/egmp/`). 3D models are the exception: see below.
3. **Git LFS**: Large binary files in this directory are tracked using Git LFS (Large File Storage) via `.gitattributes`.

## 3D models

The app ships a meshopt-compressed model (`assets/cars/egmp/2022_kia_ev6.glb`). Do not export straight into `assets/`:

1. Export the uncompressed `.glb` from Blender to `assets_src/egmp/kia_ev6/2022_kia_ev6.glb` (tracked with Git LFS).
2. Run `tool/compress_model.sh` (needs Node.js for `npx`) to write the compressed copy to `assets/cars/egmp/`.

Compression keeps the node, material and animation names the hero looks up. Quantization wraps each mesh in an unnamed child node, so the hero resolves parts through the named parent rather than assuming the named node is the mesh itself.

## Attributions

- ["2022 Kia EV6"](https://sketchfab.com/3d-models/2022-kia-ev6-44d11e83ef40492bb4bc3d9fbc41e5e0) by tonielpro520 is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Changed for this app: parts of the mesh simplified, parts separated for animation, the paint recolored, emissive lights and a plane under the hood added, and the mesh compressed.

The app shows these attributions on its licenses page; when an asset or its changes change, update `lib/cars/<platform>/licenses.dart` too.
