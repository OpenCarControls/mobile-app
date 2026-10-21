# Open Car 3D Viewer

This directory contains the Three.js 3D viewer for the Open Car App. 
It's bundled using Vite and outputs its compiled code to the `assets/web/` folder, which the Flutter `InAppWebView` loads from the APK via Android's `WebViewAssetLoader`.

## Prerequisites
- Node.js 20.19+ (or 22.12+)

## How to build

If you make changes to `src/app.js` or `index.html`, you will need to recompile the bundle:

1. Navigate to the `web_3d` directory:
   ```bash
   cd web_3d
   ```
2. Install dependencies (only needed once):
   ```bash
   npm install
   ```
3. Run the build script:
   ```bash
   npm run build
   ```

The build output will be automatically placed in `../assets/web/`, which is already referenced in `pubspec.yaml` and loaded by the Flutter webview.

## Updating the 3D model

The app ships a meshopt-compressed model (`assets/cars/egmp/2022_kia_ev6.glb`, decoded by `MeshoptDecoder` in `app.js`). Do not export straight into `assets/`:

1. Export the uncompressed `.glb` from Blender to `assets_src/egmp/kia_ev6/2022_kia_ev6.glb` (tracked with Git LFS).
2. Run `npm run compress-model` to write the compressed copy to `assets/cars/egmp/`.

Compression keeps the node, material and animation names that `app.js` and the Flutter viewer look up. Quantization wraps each mesh in an unnamed child node, so look objects up by name and traverse their children rather than assuming the named node is the mesh itself.

## Developing locally

To preview the 3D model outside of the Flutter app, you can run the Vite dev server:
```bash
npm run dev
```
