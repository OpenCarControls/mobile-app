import 'dart:async';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/transport/car_transport.dart';

/// Debug-only HTTP transport that imitates BLE over a local HTTP server.
///
/// Routes:
///   POST /cmd           — send [AppToDevice] (body: protobuf bytes)
///   GET  /state         — poll for the latest [DeviceToApp] (body: protobuf bytes)
///   POST /pairing       — open the pairing window on the device
///   POST /pair          — register the caller as a paired phone (body: sourceDeviceId bytes)
///   POST /clear-bonds   — remove all paired phones
///
/// This class is only instantiated when [kDebugMode] is true; it is not
/// referenced from release code paths.
class HttpCarTransport implements CarTransport {
  final String _baseUrl;
  final Duration _pollingInterval;

  final _controller = StreamController<DeviceToApp>.broadcast();
  Timer? _pollTimer;

  HttpCarTransport({
    required String host,
    required int port,
    required int pollingIntervalMs,
  }) : _baseUrl = 'http://$host:$port',
       _pollingInterval = Duration(milliseconds: pollingIntervalMs) {
    dev.log(
      'Polling $_baseUrl every ${pollingIntervalMs}ms',
      name: 'HttpTransport',
    );
    _startPolling();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(_pollingInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/state'));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final msg = DeviceToApp.fromBuffer(response.bodyBytes);
        if (!_controller.isClosed) _controller.add(msg);
      }
    } catch (e) {
      dev.log('Poll error: $e', name: 'HttpTransport');
    }
  }

  @override
  TransportType get transportType => TransportType.http;

  @override
  Stream<DeviceToApp> get messages => _controller.stream;

  @override
  Future<void> send(AppToDevice message) async {
    final response = await http
        .post(
          Uri.parse('$_baseUrl/cmd'),
          headers: {'Content-Type': 'application/x-protobuf'},
          body: Uint8List.fromList(message.writeToBuffer()),
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      dev.log(
        'POST /cmd failed: ${response.statusCode}',
        name: 'HttpTransport',
      );
      throw HttpTransportException('POST /cmd returned ${response.statusCode}');
    }
  }

  /// Ask the device to open its pairing window.
  Future<void> openPairingWindow() async {
    dev.log('POST /pairing', name: 'HttpTransport');
    final response = await http
        .post(Uri.parse('$_baseUrl/pairing'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpTransportException(
        'POST /pairing returned ${response.statusCode}',
      );
    }
  }

  /// Register this phone as a paired device.
  /// [sourceDeviceId] is the stable per-device identifier (UTF-8 bytes from
  /// [bleSourceDeviceIdProvider]).
  Future<void> registerAsPairedPhone(List<int> sourceDeviceId) async {
    dev.log('POST /pair', name: 'HttpTransport');
    final response = await http
        .post(
          Uri.parse('$_baseUrl/pair'),
          headers: {'Content-Type': 'application/octet-stream'},
          body: Uint8List.fromList(sourceDeviceId),
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpTransportException(
        'POST /pair returned ${response.statusCode}',
      );
    }
  }

  /// Ask the device to toggle state simulation (HTTP debug only).
  Future<void> simulate() async {
    dev.log('POST /simulate', name: 'HttpTransport');
    final response = await http
        .post(Uri.parse('$_baseUrl/simulate'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpTransportException(
        'POST /simulate returned ${response.statusCode}',
      );
    }
  }

  /// Remove all paired phones from the device.
  Future<void> clearBonds() async {
    dev.log('POST /clear-bonds', name: 'HttpTransport');
    final response = await http
        .post(Uri.parse('$_baseUrl/clear-bonds'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpTransportException(
        'POST /clear-bonds returned ${response.statusCode}',
      );
    }
  }

  /// Test connection to the HTTP server
  static Future<void> testConnection(String host, int port) async {
    final response = await http
        .get(Uri.parse('http://$host:$port/state'))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      throw HttpTransportException('Server returned ${response.statusCode}');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _controller.close();
  }
}

class HttpTransportException implements Exception {
  final String message;
  const HttpTransportException(this.message);

  @override
  String toString() => 'HttpTransportException: $message';
}
