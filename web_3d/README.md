# Open Car 3D Viewer

This directory contains the Three.js 3D viewer for the Open Car App. 
It's bundled using Vite and outputs its compiled code to the `assets/web/` folder so it can be served locally inside the Flutter `InAppWebView`.

## Prerequisites
- Node.js 20+

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

## Developing locally

To preview the 3D model outside of the Flutter app, you can run the Vite dev server:
```bash
npm run dev
```
