import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _kPrefsKey = 'paired_vehicles';

/// Where the single paired vehicle was stored before there could be several.
const _kLegacyPrefsKey = 'paired_vehicle_config';

/// A new id for a vehicle being paired.
String newPairedVehicleId() => const Uuid().v4();

/// How the app communicates with the paired device.
enum TransportPreference {
  /// Communicate over BLE when in range, MQTT otherwise.
  ble,

  /// Communicate over the HTTP debug server (debug builds only).
  http,
}

/// One paired vehicle, stored as part of [PairedVehicles].
class PairedVehicleConfig {
  /// Identifies this vehicle in the app and keys what is stored for it. Unique
  /// among the paired vehicles, even two of the same platform. A vehicle
  /// migrated from the single-vehicle format has its platform name, so what
  /// was already stored under that key stays its own.
  final String id;

  /// The name the user gave it; null shows the platform's.
  final String? name;

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

  /// The device's MQTT client ID, which names its topics. Reported by the
  /// device over BLE; null until it has, and MQTT stays off until then.
  final String? mqttClientId;

  const PairedVehicleConfig({
    String? id,
    this.name,
    required this.vehicleId,
    required this.bleRemoteId,
    required this.transportPreference,
    this.httpHost,
    this.httpPort,
    this.mqttBrokerHost,
    this.mqttBrokerPort,
    this.mqttUsername,
    this.mqttPassword,
    this.mqttClientId,
  }) : id = id ?? vehicleId;

  /// A copy with the given fields replaced. [clearName] goes back to the
  /// platform's name.
  PairedVehicleConfig copyWith({
    String? id,
    String? name,
    bool clearName = false,
    String? mqttClientId,
  }) => PairedVehicleConfig(
    id: id ?? this.id,
    name: clearName ? null : name ?? this.name,
    vehicleId: vehicleId,
    bleRemoteId: bleRemoteId,
    transportPreference: transportPreference,
    httpHost: httpHost,
    httpPort: httpPort,
    mqttBrokerHost: mqttBrokerHost,
    mqttBrokerPort: mqttBrokerPort,
    mqttUsername: mqttUsername,
    mqttPassword: mqttPassword,
    mqttClientId: mqttClientId ?? this.mqttClientId,
  );

  /// Keys what is stored per vehicle (saved layouts, cached state, activity
  /// log, unsupported commands).
  String get storageKey => id;

  /// Whether [other] is a pairing of the same device as this one.
  bool isSameDevice(PairedVehicleConfig other) {
    if (bleRemoteId.isNotEmpty) return bleRemoteId == other.bleRemoteId;
    return other.bleRemoteId.isEmpty &&
        vehicleId == other.vehicleId &&
        httpHost == other.httpHost &&
        httpPort == other.httpPort;
  }

  /// Whether this vehicle is reached over BLE when in range: paired over BLE
  /// (not the HTTP debug path) with a bonded device to connect to.
  bool get usesBle =>
      transportPreference == TransportPreference.ble && bleRemoteId.isNotEmpty;

  Map<String, dynamic> _toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'vehicleId': vehicleId,
    'bleRemoteId': bleRemoteId,
    'transportPreference': transportPreference.name,
    if (httpHost != null) 'httpHost': httpHost,
    if (httpPort != null) 'httpPort': httpPort,
    if (mqttBrokerHost != null) 'mqttBrokerHost': mqttBrokerHost,
    if (mqttBrokerPort != null) 'mqttBrokerPort': mqttBrokerPort,
    if (mqttUsername != null) 'mqttUsername': mqttUsername,
    if (mqttPassword != null) 'mqttPassword': mqttPassword,
    if (mqttClientId != null) 'mqttClientId': mqttClientId,
  };

  factory PairedVehicleConfig._fromJson(Map<String, dynamic> j) =>
      PairedVehicleConfig(
        id: j['id'] as String?,
        name: j['name'] as String?,
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
        mqttClientId: j['mqttClientId'] as String?,
      );
}

/// The paired vehicles and which one is current: the only one with live links.
///
/// Saved to SharedPreferences as JSON whenever it changes. Loaded once at app
/// startup before [runApp].
class PairedVehicles {
  const PairedVehicles({this.vehicles = const [], this.currentId});

  /// Just [vehicle], or nothing when it's null.
  factory PairedVehicles.of(PairedVehicleConfig? vehicle) => vehicle == null
      ? const PairedVehicles()
      : PairedVehicles(vehicles: [vehicle], currentId: vehicle.id);

  final List<PairedVehicleConfig> vehicles;
  final String? currentId;

  /// The current vehicle; null only when none is paired.
  PairedVehicleConfig? get current {
    for (final vehicle in vehicles) {
      if (vehicle.id == currentId) return vehicle;
    }
    return vehicles.isEmpty ? null : vehicles.first;
  }

  /// Loads the stored vehicles, moving an install that still has the
  /// single-vehicle format to this one. Corrupt data reads as nothing paired.
  static Future<PairedVehicles> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        return PairedVehicles(
          vehicles: [
            for (final vehicle in json['vehicles'] as List)
              PairedVehicleConfig._fromJson(vehicle as Map<String, dynamic>),
          ],
          currentId: json['currentId'] as String?,
        );
      } catch (_) {
        return const PairedVehicles();
      }
    }

    final legacy = prefs.getString(_kLegacyPrefsKey);
    if (legacy == null) return const PairedVehicles();
    try {
      final migrated = PairedVehicles.of(
        PairedVehicleConfig._fromJson(
          jsonDecode(legacy) as Map<String, dynamic>,
        ),
      );
      await migrated.save();
      await prefs.remove(_kLegacyPrefsKey);
      return migrated;
    } catch (_) {
      return const PairedVehicles();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kPrefsKey,
      jsonEncode({
        'vehicles': [for (final vehicle in vehicles) vehicle._toJson()],
        if (currentId != null) 'currentId': currentId,
      }),
    );
  }
}
