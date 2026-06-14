import 'dart:io';

import 'package:build/build.dart';
import 'package:glob/glob.dart';

/// A [Builder] that invokes `protoc` (with the Dart plugin) on every
/// `.proto` file found under `contracts/`. All proto files are registered
/// as inputs so the builder re-runs whenever any of them changes.
///
/// Generated Dart files are written directly to `lib/generated/` (via
/// dart:io, the same directory protoc targets) and a stamp file is written
/// via [BuildStep.writeAsString] so build_runner tracks the output and only
/// re-runs when inputs change.
class ProtoBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
    r'$package$': ['lib/generated/.proto_build.stamp'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Discover all .proto files and register them as tracked dependencies.
    final protoAssets = <AssetId>[];
    await for (final asset in buildStep.findAssets(
      Glob('contracts/**/*.proto'),
    )) {
      // Reading the asset content registers it as a dependency: if the file
      // changes, build_runner will invalidate this builder's output and re-run.
      await buildStep.readAsString(asset);
      protoAssets.add(asset);
    }

    if (protoAssets.isEmpty) return;

    if (!await _protocAvailable()) {
      throw StateError(
        'protoc not found on PATH. '
        'Ensure protobuf-compiler is installed (it is declared in .devcontainer/Dockerfile).',
      );
    }

    final env = _buildEnv();

    if (!await _dartPluginAvailable(env)) {
      throw StateError(
        'protoc-gen-dart not found. '
        'Run: dart pub global activate protoc_plugin',
      );
    }

    Directory('lib/generated').createSync(recursive: true);

    final result = await Process.run('protoc', [
      '--proto_path=contracts',
      '--dart_out=grpc:lib/generated',
      ...protoAssets.map((id) => id.path),
    ], environment: env);

    if (result.exitCode != 0) {
      throw StateError('protoc failed:\n${result.stderr}');
    }

    // Write the stamp file so build_runner knows the builder ran successfully.
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/generated/.proto_build.stamp'),
      DateTime.now().toIso8601String(),
    );
  }

  Future<bool> _protocAvailable() async {
    final cmd = Platform.isWindows ? 'where' : 'which';
    final result = await Process.run(cmd, ['protoc']);
    return result.exitCode == 0;
  }

  Future<bool> _dartPluginAvailable(Map<String, String> env) async {
    final cmd = Platform.isWindows ? 'where' : 'which';
    final result = await Process.run(cmd, [
      'protoc-gen-dart',
    ], environment: env);
    return result.exitCode == 0;
  }

  /// Returns a copy of the current environment with the Dart pub-cache bin
  /// directory prepended to PATH, so `protoc` can find `protoc-gen-dart`
  /// even when build_runner spawns this builder in a shell that hasn't
  /// sourced the user's profile.
  Map<String, String> _buildEnv() {
    final pubCacheBin = _pubCacheBinDir();
    final current = Platform.environment;
    final existingPath = current['PATH'] ?? '';
    final separator = Platform.isWindows ? ';' : ':';
    return {...current, 'PATH': '$pubCacheBin$separator$existingPath'};
  }

  String _pubCacheBinDir() {
    // Respect PUB_CACHE env var if set, otherwise fall back to the default.
    if (Platform.environment.containsKey('PUB_CACHE')) {
      return '${Platform.environment['PUB_CACHE']}/bin';
    }
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      return '$localAppData/Pub/Cache/bin';
    }
    return '${Platform.environment['HOME']}/.pub-cache/bin';
  }
}
