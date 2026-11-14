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
    final tls = mqttTlsFiles(broker);
    // mTLS sends no password: the broker takes the phone's identity from its
    // certificate.
    final mtls = tls?.clientCertFile != null;
    final username = mtls ? '' : _string(broker['username'], 'broker.username');
    final password = mtls ? '' : _string(broker['password'], 'broker.password');

    Future<String> pem(String? path) async {
      if (path == null) return '';
      final id = AssetId(exampleId.package, path);
      if (!await buildStep.canRead(id)) {
        throw StateError(
          'MQTT TLS: $path not found (paths are relative to the app root, '
          'under certs/).',
        );
      }
      return buildStep.readAsString(id);
    }

    final caPem = await pem(tls?.caCertFile);
    final clientCertPem = await pem(tls?.clientCertFile);
    final clientKeyPem = await pem(tls?.clientKeyFile);

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
      ..writeln('// TLS (broker.tls): no CA means plain TCP.')
      ..writeln('const String kMqttCaCertPem = ${jsonEncode(caPem)};')
      ..writeln(
        'const String kMqttClientCertPem = ${jsonEncode(clientCertPem)};',
      )
      ..writeln(
        'const String kMqttClientKeyPem = ${jsonEncode(clientKeyPem)};',
      )
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

/// The certificate files of the `[broker]` table, or null without TLS.
class MqttTlsFiles {
  const MqttTlsFiles({
    required this.caCertFile,
    this.clientCertFile,
    this.clientKeyFile,
  });

  final String caCertFile;

  /// Set together with [clientKeyFile] for mTLS (`auth_mode = "mtls"`).
  final String? clientCertFile;
  final String? clientKeyFile;
}

/// Checks the TLS settings of the `[broker]` table: `tls` (default false),
/// `auth_mode` (`basic` or `mtls`, default `basic`) and the certificate files.
/// mTLS needs TLS, and TLS needs the CA the broker's certificate chains to.
MqttTlsFiles? mqttTlsFiles(Map<String, Object?> broker) {
  final tls = broker['tls'] ?? false;
  if (tls is! bool) throw StateError('Expected [broker.tls] to be a bool.');
  final authMode = broker['auth_mode'] ?? 'basic';
  if (authMode != 'basic' && authMode != 'mtls') {
    throw StateError(
      '[broker.auth_mode] must be "basic" or "mtls", got "$authMode".',
    );
  }
  final mtls = authMode == 'mtls';
  if (!tls) {
    if (mtls) {
      throw StateError(
        '[broker.auth_mode] = "mtls" needs [broker.tls] = true.',
      );
    }
    return null;
  }
  String file(String key) {
    final value = broker[key];
    if (value is String && value.isNotEmpty) return value;
    throw StateError('[broker.$key] is required with [broker.tls] = true.');
  }

  return MqttTlsFiles(
    caCertFile: file('ca_cert_file'),
    clientCertFile: mtls ? file('client_cert_file') : null,
    clientKeyFile: mtls ? file('client_key_file') : null,
  );
}

