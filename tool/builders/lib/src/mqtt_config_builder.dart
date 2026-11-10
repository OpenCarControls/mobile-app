import 'dart:convert';

import 'package:build/build.dart';
import 'package:toml/toml.dart';

class MqttConfigBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    'config.toml.example': ['lib/config/mqtt_broker_config.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Always read the example file for defaults.
    final exampleId = buildStep.inputId;
    var source = await buildStep.readAsString(exampleId);

    // If a local config.toml exists, use it instead (developer / CI override).
    final overrideId = AssetId(exampleId.package, 'config.toml');
    if (await buildStep.canRead(overrideId)) {
      source = await buildStep.readAsString(overrideId);
    }

    final doc = TomlDocument.parse(source);
    final config = doc.toMap();

    final broker = _map(config['broker'], 'broker');
    final debugServer = _map(config['debug_server'], 'debug_server');

    final host = _string(broker['host'], 'broker.host');
    final port = _int(broker['port'], 'broker.port');
    final username = _string(broker['username'], 'broker.username');
    final password = _string(broker['password'], 'broker.password');
    final debugHost = _string(debugServer['host'], 'debug_server.host');
    final debugPort = _int(debugServer['port'], 'debug_server.port');
    final debugPollingIntervalMs = _int(
      debugServer['polling_interval_ms'],
      'debug_server.polling_interval_ms',
    );

    final outputId = AssetId(
      exampleId.package,
      'lib/config/mqtt_broker_config.g.dart',
    );

    final buffer = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
      ..writeln('// Source: config.toml (or config.toml.example as fallback)')
      ..writeln()
      ..writeln('const String kMqttBrokerHost = ${jsonEncode(host)};')
      ..writeln('const int kMqttBrokerPort = $port;')
      ..writeln('const String kMqttUsername = ${jsonEncode(username)};')
      ..writeln('const String kMqttPassword = ${jsonEncode(password)};')
      ..writeln()
      ..writeln('// Debug HTTP server (used only in debug builds).')
      ..writeln('const String kDebugServerHost = ${jsonEncode(debugHost)};')
      ..writeln('const int kDebugServerPort = $debugPort;')
      ..writeln(
        'const int kDebugServerPollingIntervalMs = $debugPollingIntervalMs;',
      );

    await buildStep.writeAsString(outputId, buffer.toString());
  }

  Map<String, Object?> _map(Object? value, String field) {
    if (value is Map<String, Object?>) return value;
    throw StateError('Expected [$field] to be a table.');
  }

  String _string(Object? value, String field) {
    if (value is String) return value;
    throw StateError('Expected [$field] to be a string.');
  }

  int _int(Object? value, String field) {
    if (value is int) return value;
    throw StateError('Expected [$field] to be an int.');
  }
}
