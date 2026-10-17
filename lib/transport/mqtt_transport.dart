import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqtt5_client/mqtt5_server_client.dart';
import 'package:open_car_app/config/mqtt_broker_config.g.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:typed_data/typed_data.dart' as typed;

import 'car_transport.dart';

class MqttCarTransport with WidgetsBindingObserver implements CarTransport {
  final _controller = StreamController<DeviceToApp>.broadcast();
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>?
  _updatesSubscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _backgroundPauseTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;
  bool _heartbeatPaused = false;

  static const _heartbeatInterval = Duration(seconds: 5);
  static const _backgroundPauseDelay = Duration(seconds: 30);

  late final MqttServerClient _client;
  late final String _cmdTopic;
  late final String _dataTopic;
  late final int _platformId;
  late final List<int> _sourceDeviceId;
  // Heartbeat IDs start at 2^32 so they never collide with command IDs, which
  // the firmware echoes back in CommandResponse.message_id.
  Int64 _heartbeatMessageId = Int64.ONE << 32;

  MqttCarTransport({
    required String commandTopicTemplate,
    required String dataTopicTemplate,
    required String connectionClientId,
    required int platformId,
    required List<int> sourceDeviceId,
  }) {
    _platformId = platformId;
    _sourceDeviceId = sourceDeviceId;
    _cmdTopic = commandTopicTemplate.replaceAll('{client_id}', kMqttClientId);
    _dataTopic = dataTopicTemplate.replaceAll('{client_id}', kMqttClientId);

    _client = MqttServerClient(kMqttBrokerHost, connectionClientId)
      ..port = kMqttBrokerPort
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..logging(on: kDebugMode)
      ..onDisconnected = _onDisconnected
      ..onConnected = _onConnected
      ..onAutoReconnected = _onAutoReconnected
      ..onSubscribed = _onSubscribed
      ..onSubscribeFail = _onSubscribeFail;

    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(connectionClientId)
        .startClean();

    WidgetsBinding.instance.addObserver(this);

    unawaited(_connect());
    dev.log(
      'Connecting to $kMqttBrokerHost:$kMqttBrokerPort',
      name: 'MqttTransport',
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _backgroundPauseTimer?.cancel();
      _backgroundPauseTimer = null;
      if (_heartbeatPaused) {
        _heartbeatPaused = false;
        dev.log('App resumed — restarting heartbeat', name: 'MqttTransport');
        _startHeartbeat();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _backgroundPauseTimer ??= Timer(_backgroundPauseDelay, () {
        _backgroundPauseTimer = null;
        _heartbeatPaused = true;
        _heartbeatTimer?.cancel();
        _heartbeatTimer = null;
        dev.log('App backgrounded — heartbeat paused', name: 'MqttTransport');
      });
    }
  }

  Future<void> _connect() async {
    if (_disposed) return;

    final state = _client.connectionStatus?.state;
    if (state == MqttConnectionState.connected ||
        state == MqttConnectionState.connecting) {
      return;
    }

    try {
      await _client.connect(kMqttUsername, kMqttPassword);
      if (_client.connectionStatus?.state != MqttConnectionState.connected) {
        _scheduleReconnect('connect completed but not connected');
      }
    } on MqttNoConnectionException catch (e) {
      _scheduleReconnect('no connection: $e');
    } on Exception catch (e) {
      _scheduleReconnect('connect exception: $e');
    }
  }

  void _scheduleReconnect(String reason) {
    if (_disposed) return;
    if (_reconnectTimer?.isActive ?? false) return;

    final delaySeconds = math.min(30, 1 << _reconnectAttempt);
    _reconnectAttempt = math.min(_reconnectAttempt + 1, 5);
    dev.log(
      'Scheduling reconnect in ${delaySeconds}s ($reason)',
      name: 'MqttTransport',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectTimer = null;
      unawaited(_connect());
    });
  }

  void _onConnected() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    dev.log('Connected; subscribing to $_dataTopic', name: 'MqttTransport');
    _client.subscribe(_dataTopic, MqttQos.atLeastOnce);
    _startHeartbeat();
    // Cancel any existing subscription before adding a new one — _onConnected
    // fires on every CONNACK (initial connection and each auto-reconnect), so
    // without this guard we would accumulate duplicate listeners.
    _updatesSubscription?.cancel();
    _updatesSubscription = _client.updates?.listen(_onMessage);
  }

  void _startHeartbeat() {
    if (_heartbeatPaused) return;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => _sendHeartbeat(),
    );
    _sendHeartbeat(); // send immediately on connect
  }

  void _sendHeartbeat() {
    if (_client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }

    final msg = AppToDevice()
      ..messageId = _heartbeatMessageId++
      ..platformId = _platformId
      ..sourceDeviceId = _sourceDeviceId
      ..heartbeat = true;
    final buffer = typed.Uint8Buffer()..addAll(msg.writeToBuffer());
    _client.publishMessage(_cmdTopic, MqttQos.atLeastOnce, buffer);
    dev.log('Heartbeat sent', name: 'MqttTransport');
  }

  void _onAutoReconnected() {
    dev.log('Auto-reconnected', name: 'MqttTransport');
    // mqtt5_client re-subscribes automatically when resubscribeOnAutoReconnect
    // is true (the default).  No manual action needed here.
  }

  void _onSubscribed(MqttSubscription subscription) {
    dev.log(
      'Subscription confirmed: ${subscription.topic.rawTopic}',
      name: 'MqttTransport',
    );
  }

  void _onSubscribeFail(MqttSubscription subscription) {
    dev.log(
      'Subscription REJECTED by broker: ${subscription.topic.rawTopic}',
      name: 'MqttTransport',
    );
  }

  void _onDisconnected() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_disposed) return;
    final origin = _client.connectionStatus?.disconnectionOrigin;
    final reason = _client.connectionStatus?.reasonCode;
    dev.log(
      'Disconnected — origin: $origin, reasonCode: $reason',
      name: 'MqttTransport',
    );
    // Safety net: explicit retry loop for cases where autoReconnect does not
    // recover (e.g. initial startup while broker is down).
    _scheduleReconnect('disconnected');
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final m in messages) {
      if (kDebugMode) {
        dev.log(
          'Message received on topic: "${m.topic}" (expected: "$_dataTopic")',
          name: 'MqttTransport',
        );
      }
      if (m.topic != _dataTopic) continue;
      final publish = m.payload as MqttPublishMessage;
      final bytes = publish.payload.message;
      if (bytes == null || bytes.isEmpty) continue;
      try {
        final msg = DeviceToApp.fromBuffer(bytes);
        if (kDebugMode) {
          dev.log(
            'Decoded DeviceToApp (${bytes.length} bytes)',
            name: 'MqttTransport',
          );
        }
        if (!_controller.isClosed) _controller.add(msg);
      } on Exception catch (e) {
        dev.log('Malformed protobuf discarded: $e', name: 'MqttTransport');
      }
    }
  }

  @override
  TransportType get transportType => TransportType.mqtt;

  @override
  Stream<DeviceToApp> get messages => _controller.stream;

  @override
  Future<void> send(AppToDevice message) async {
    if (!message.hasBasicCommandBytes() && !message.hasHeartbeat()) {
      throw const CarTransportException(
        'This command is only available over Bluetooth.',
      );
    }
    if (_client.connectionStatus?.state != MqttConnectionState.connected) {
      throw const CarTransportException(
        'Not connected to the vehicle. Check your network connection.',
      );
    }

    final buffer = typed.Uint8Buffer()..addAll(message.writeToBuffer());
    _client.publishMessage(_cmdTopic, MqttQos.atLeastOnce, buffer);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _backgroundPauseTimer?.cancel();
    _backgroundPauseTimer = null;
    _updatesSubscription?.cancel();
    _client.disconnect();
    _controller.close();
  }
}
