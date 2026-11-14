import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // flutter_scene:init:start
    // Import .glb and .fscene sources under assets/, loadable by source path
    // with loadScene (and hot-reloadable). A no-op when there are no scenes.
    // The models are symlinks to the app's files, which discovery skips
    // (it lists with followLinks: false), so they are named explicitly.
    buildScenes(
      buildInput: input,
      buildOutput: output,
      inputFilePaths: [
        'assets/models/ev6_meshopt.glb',
        'assets/models/ev6_raw.glb',
      ],
    );
    // Compile .fmat materials under assets/, loadable by source path with
    // loadFmatMaterial (and hot-reloadable). A no-op when there are none.
    await buildMaterials(buildInput: input, buildOutput: output);
    // flutter_scene:init:end
  });
}
