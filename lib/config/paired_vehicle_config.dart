import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _kPrefsKey = 'paired_vehicle_config';

/// How the app communicates with the paired device.
enum TransportPreference {
  /// Communicate over BLE when in range, MQTT otherwise.
  ble,

  /// Communicate over the HTTP debug server (debug builds only).
  http,
}

/// Persisted pairing state for the one paired vehicle.
///
/// Saved to SharedPreferences as JSON on pairing completion and cleared on
/// unpair. Loaded once at app startup before [runApp].
class PairedVehicleConfig {
  /// Matches [VehicleDefinition.platformName] — used to look up the vehicle.
  final String vehicleId;

  /// Remote ID of the bonded BLE device. Empty string when paired via HTTP.
  final String bleRemoteId;

  final TransportPreference transportPreference;

  /// HTTP debug server host. Non-null when [transportPreference] is [TransportPreference.http].
  final String? httpHost;

  /// HTTP debug server port. Non-null when [transportPreference] is [TransportPreference.http].
  final int? httpPort;

  // ── Reserved for future MQTT configuration wizard ──────────────────────────
  // These fields are null until an MQTT setup step is added to the wizard.
  // When non-null, [carTransportProvider] will use them instead of the
  // compile-time constants from mqtt_broker_config.g.dart.
  final String? mqttBrokerHost;
  final int? mqttBrokerPort;
  final String? mqttUsername;
  final String? mqttPassword;

  const PairedVehicleConfig({
    required this.vehicleId,
    required this.bleRemoteId,
    required this.transportPreference,
    this.httpHost,
    this.httpPort,
    this.mqttBrokerHost,
    this.mqttBrokerPort,
    this.mqttUsername,
    this.mqttPassword,
  });

  /// Whether this vehicle is reached over BLE when in range: paired over BLE
  /// (not the HTTP debug path) with a bonded device to connect to.
  bool get usesBle =>
      transportPreference == TransportPreference.ble && bleRemoteId.isNotEmpty;

  static Future<PairedVehicleConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null) return null;
    try {
      return PairedVehicleConfig._fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      // Corrupt data — treat as unpaired.
      return null;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefsKey, jsonEncode(_toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefsKey);
  }

  Map<String, dynamic> _toJson() => {
    'vehicleId': vehicleId,
    'bleRemoteId': bleRemoteId,
    'transportPreference': transportPreference.name,
    if (httpHost != null) 'httpHost': httpHost,
    if (httpPort != null) 'httpPort': httpPort,
    if (mqttBrokerHost != null) 'mqttBrokerHost': mqttBrokerHost,
    if (mqttBrokerPort != null) 'mqttBrokerPort': mqttBrokerPort,
    if (mqttUsername != null) 'mqttUsername': mqttUsername,
    if (mqttPassword != null) 'mqttPassword': mqttPassword,
  };

  factory PairedVehicleConfig._fromJson(Map<String, dynamic> j) =>
      PairedVehicleConfig(
        vehicleId: j['vehicleId'] as String,
        bleRemoteId: j['bleRemoteId'] as String,
        transportPreference: TransportPreference.values.byName(
          j['transportPreference'] as String,
        ),
        httpHost: j['httpHost'] as String?,
        httpPort: j['httpPort'] as int?,
        mqttBrokerHost: j['mqttBrokerHost'] as String?,
        mqttBrokerPort: j['mqttBrokerPort'] as int?,
        mqttUsername: j['mqttUsername'] as String?,
        mqttPassword: j['mqttPassword'] as String?,
      );
}
