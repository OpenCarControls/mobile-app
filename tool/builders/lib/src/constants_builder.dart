import 'dart:convert';

import 'package:build/build.dart';
import 'package:toml/toml.dart';

class ConstantsBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    'contracts/opencar/cars/{{vehicle}}/v1/meta.toml': [
      'lib/cars/{{vehicle}}/constants.g.dart',
    ],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    final segments = input.pathSegments;
    if (segments.length < 6) {
      throw StateError('Unexpected meta.toml path: ${input.path}');
    }

    final vehicle = segments[3];

    final transportId = AssetId(
      input.package,
      'contracts/opencar/core/v1/transport.toml',
    );

    final metaDoc = TomlDocument.parse(await buildStep.readAsString(input));
    final transportDoc = TomlDocument.parse(
      await buildStep.readAsString(transportId),
    );

    final meta = metaDoc.toMap();
    final transport = transportDoc.toMap();

    final platformName = _string(meta['platform_name'], 'platform_name');
    final platformIdHex = _string(meta['platform_id'], 'platform_id');
    final platformId = _parseHexUint32(platformIdHex, 'platform_id');
    final canBusCount = _int(meta['can_bus_count'], 'can_bus_count');

    final mqtt = _map(transport['mqtt'], 'mqtt');
    final ble = _map(transport['ble'], 'ble');
    final bleService = _map(ble['service'], 'ble.service');
    final bleCharacteristics = _map(
      ble['characteristics'],
      'ble.characteristics',
    );
    final appToDevice = _map(
      bleCharacteristics['app_to_device'],
      'ble.characteristics.app_to_device',
    );
    final deviceToApp = _map(
      bleCharacteristics['device_to_app'],
      'ble.characteristics.device_to_app',
    );
    final blePairing = _map(ble['pairing'], 'ble.pairing');
    final blePayload = _map(ble['payload'], 'ble.payload');
    final bleFragmentation = _map(ble['fragmentation'], 'ble.fragmentation');

    final mqttCommandTemplate = _string(
      mqtt['command_topic_template'],
      'mqtt.command_topic_template',
    );
    final mqttDataTemplate = _string(
      mqtt['data_topic_template'],
      'mqtt.data_topic_template',
    );

    final bleServiceName = _string(bleService['name'], 'ble.service.name');
    final bleServiceUuid = _string(bleService['uuid'], 'ble.service.uuid');
    final appToDeviceUuid = _string(
      appToDevice['uuid'],
      'ble.characteristics.app_to_device.uuid',
    );
    final deviceToAppUuid = _string(
      deviceToApp['uuid'],
      'ble.characteristics.device_to_app.uuid',
    );
    final blePairingWindowSeconds = _int(
      blePairing['pairing_window_seconds'],
      'ble.pairing.pairing_window_seconds',
    );
    final bleScanTimeoutSeconds = _int(
      blePairing['scan_timeout_seconds'],
      'ble.pairing.scan_timeout_seconds',
    );
    final bleAttMtu = _int(blePayload['att_mtu'], 'ble.payload.att_mtu');
    final bleMaxChunkBytes = _int(
      blePayload['max_chunk_bytes'],
      'ble.payload.max_chunk_bytes',
    );
    final bleMaxMessageBytes = _int(
      blePayload['max_message_bytes'],
      'ble.payload.max_message_bytes',
    );
    int fragmentation(String key) =>
        _int(bleFragmentation[key], 'ble.fragmentation.$key');
    final bleChunkHeaderBytes = fragmentation('header_bytes');
    final bleChunkLastFlag = fragmentation('last_chunk_flag');
    final bleChunkIndexMask = fragmentation('chunk_index_mask');
    final bleMaxChunks = fragmentation('max_chunks');
    final bleMinAttMtu = fragmentation('min_att_mtu');
    final bleReassemblyTimeoutMs = fragmentation('reassembly_timeout_ms');

    final outputId = AssetId(
      input.package,
      'lib/cars/$vehicle/constants.g.dart',
    );

    final buffer = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
      ..writeln('// Source: ${input.path} + ${transportId.path}')
      ..writeln()
      ..writeln('const String kPlatformName = ${jsonEncode(platformName)};')
      ..writeln(
        'const int kPlatformId = 0x${platformId.toRadixString(16).padLeft(8, '0').toUpperCase()};',
      )
      ..writeln('const int kCanBusCount = $canBusCount;')
      ..writeln()
      ..writeln(
        'const String kMqttCommandTopicTemplate = ${jsonEncode(mqttCommandTemplate)};',
      )
      ..writeln(
        'const String kMqttDataTopicTemplate = ${jsonEncode(mqttDataTemplate)};',
      )
      ..writeln()
      ..writeln('const String kBleServiceName = ${jsonEncode(bleServiceName)};')
      ..writeln('const String kBleServiceUuid = ${jsonEncode(bleServiceUuid)};')
      ..writeln(
        'const String kBleAppToDeviceCharacteristicUuid = ${jsonEncode(appToDeviceUuid)};',
      )
      ..writeln(
        'const String kBleDeviceToAppCharacteristicUuid = ${jsonEncode(deviceToAppUuid)};',
      )
      ..writeln()
      ..writeln(
        'const int kBlePairingWindowSeconds = $blePairingWindowSeconds;',
      )
      ..writeln('const int kBleScanTimeoutSeconds = $bleScanTimeoutSeconds;')
      ..writeln()
      ..writeln('const int kBleAttMtu = $bleAttMtu;')
      ..writeln('const int kBleMaxChunkBytes = $bleMaxChunkBytes;')
      ..writeln('const int kBleMaxMessageBytes = $bleMaxMessageBytes;')
      ..writeln()
      ..writeln('const int kBleChunkHeaderBytes = $bleChunkHeaderBytes;')
      ..writeln('const int kBleChunkLastFlag = $bleChunkLastFlag;')
      ..writeln('const int kBleChunkIndexMask = $bleChunkIndexMask;')
      ..writeln('const int kBleMaxChunks = $bleMaxChunks;')
      ..writeln('const int kBleMinAttMtu = $bleMinAttMtu;')
      ..writeln('const int kBleReassemblyTimeoutMs = $bleReassemblyTimeoutMs;');

    await buildStep.writeAsString(outputId, buffer.toString());
  }

  Map<String, Object?> _map(Object? value, String field) {
    if (value is Map<String, Object?>) {
      return value;
    }
    throw StateError('Expected [$field] to be a table.');
  }

  String _string(Object? value, String field) {
    if (value is String) {
      return value;
    }
    throw StateError('Expected [$field] to be a string.');
  }

  int _int(Object? value, String field) {
    if (value is int) {
      return value;
    }
    throw StateError('Expected [$field] to be an int.');
  }

  int _parseHexUint32(String raw, String field) {
    final normalized = raw.startsWith('0x') || raw.startsWith('0X')
        ? raw.substring(2)
        : raw;
    final value = int.tryParse(normalized, radix: 16);
    if (value == null) {
      throw StateError('Expected [$field] to be a hex string, got: $raw');
    }
    if (value < 0 || value > 0xFFFFFFFF) {
      throw StateError('Expected [$field] to fit uint32, got: $raw');
    }
    return value;
  }
}
