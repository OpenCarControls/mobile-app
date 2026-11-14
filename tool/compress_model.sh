#!/usr/bin/env bash
# Compresses the uncompressed E-GMP model export in assets_src/ into the
# meshopt-compressed copy the app ships. Needs Node.js (npx). Keeps the
# node, material and animation names the hero looks up.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

npx --yes @gltf-transform/cli@4.5.1 meshopt \
  assets_src/egmp/kia_ev6/2022_kia_ev6.glb \
  assets/cars/egmp/2022_kia_ev6.glb \
  --quantization-volume scene --quantize-position 16
