# Source Assets (assets_src)

This directory contains raw design assets, 3D source files (such as `.blend` Blender files), high-resolution textures, and workspace files.

## Guidelines

1. **Keep raw sources here**: Do **not** place `.blend` or raw project files in `assets/`. The `assets/` folder is packaged directly into the compiled Flutter application, whereas this `assets_src/` folder is ignored by Flutter.
2. **Export runtime assets**: Export final production-ready assets (e.g., `.glb` for 3D models, `.png`/`.jpg` for compressed images) to the appropriate subfolder in `assets/` (e.g., `assets/cars/egmp/`).
3. **Git LFS**: Large binary files in this directory are tracked using Git LFS (Large File Storage) via `.gitattributes`.

## Attributions

- ["2022 Kia EV6"](https://sketchfab.com/3d-models/2022-kia-ev6-44d11e83ef40492bb4bc3d9fbc41e5e0) by tonielpro520 is licensed under Creative Commons Attribution.
