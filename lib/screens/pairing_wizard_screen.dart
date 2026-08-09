import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/providers/ble_provider.dart';
import 'package:open_car_app/cars/virtual_car/constants.g.dart';
import 'package:open_car_app/config/mqtt_broker_config.g.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/transport/http_transport.dart';
import 'package:permission_handler/permission_handler.dart';

// ── Wizard step state machine ─────────────────────────────────────────────────

enum _Step {
  /// Prompt shown before scan starts — user should hold the pairing button.
  prompt,

  /// Actively scanning for the device's BLE advertisement.
  scanning,

  /// Device found; waiting for the user to tap "Pair".
  found,

  /// Bond or HTTP pair in progress.
  pairing,

  /// Fatal error; user can retry.
  error,
}

// ── Screen ────────────────────────────────────────────────────────────────────

class PairingWizardScreen extends ConsumerStatefulWidget {
  const PairingWizardScreen({super.key});

  @override
  ConsumerState<PairingWizardScreen> createState() =>
      _PairingWizardScreenState();
}

class _PairingWizardScreenState extends ConsumerState<PairingWizardScreen> {
  _Step _step = _Step.prompt;
  String? _foundDeviceId;
  String? _foundDeviceName;
  String _errorMessage = '';
  bool _staleBondWarning = false;

  // Scan countdown
  int _remainingSeconds = kBleScanTimeoutSeconds;
  Timer? _scanTimeoutTimer;
  Timer? _countdownTimer;
  StreamSubscription<DiscoveredDevice>? _scanSubscription;

  // HTTP mode (debug only)
  bool _httpMode = false;
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '4242');
  bool _httpTesting = false;
  bool _httpPairingWindowOpen = false;
  String _httpTestResult = '';

  @override
  void dispose() {
    _stopScan();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  // ── Scan lifecycle ──────────────────────────────────────────────────────────

  Future<void> _startScan() async {
    final granted = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request().then((s) => s.values.every((v) => v.isGranted));

    if (!granted) {
      _setError('Bluetooth permission denied. Grant it in app settings.');
      return;
    }

    if (!mounted) return;

    // Only one vehicle platform for now — use its service UUID.
    final vehicle = ref.read(availableVehiclesProvider).first;

    setState(() {
      _step = _Step.scanning;
      _remainingSeconds = kBleScanTimeoutSeconds;
    });

    final ble = ref.read(bleProvider);
    _scanSubscription = ble
        .scanForDevices(
          withServices: [Uuid.parse(vehicle.bleServiceUuid)],
          scanMode: ScanMode.lowLatency,
        )
        .listen((device) {
          if (_step != _Step.scanning) return;
          dev.log('Wizard found device: ${device.id}', name: 'PairingWizard');
          _stopScan();
          if (mounted) {
            setState(() {
              _foundDeviceId = device.id;
              _foundDeviceName = device.name;
              _step = _Step.found;
            });
          }
        });

    _scanTimeoutTimer = Timer(Duration(seconds: kBleScanTimeoutSeconds), () {
      if (_step == _Step.scanning) {
        _stopScan();
        _setError(
          'No device found. Make sure you are holding the pairing button and '
          'try again.',
        );
      }
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _step != _Step.scanning) return;
      setState(() => _remainingSeconds--);
    });
  }

  void _stopScan() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    // flutter_reactive_ble stops scanning automatically when the subscription
    // is cancelled — no explicit stopScan() call needed.
  }

  // ── BLE pairing ─────────────────────────────────────────────────────────────

  Future<void> _pairBle() async {
    final deviceId = _foundDeviceId!;
    setState(() => _step = _Step.pairing);

    final ble = ref.read(bleProvider);
    StreamSubscription<ConnectionStateUpdate>? connSub;

    try {
      dev.log('Wizard: connecting to $deviceId', name: 'PairingWizard');

      final connectedCompleter = Completer<void>();
      // Fires if the connection drops *after* we connected — stale-bond
      // scenario where the firmware closes the link because the phone is no
      // longer in its bond table.
      final disconnectCompleter = Completer<void>();

      connSub = ble
          .connectToDevice(
            id: deviceId,
            connectionTimeout: Duration(seconds: kBlePairingWindowSeconds),
          )
          .listen(
            (update) {
              switch (update.connectionState) {
                case DeviceConnectionState.connected:
                  if (!connectedCompleter.isCompleted) {
                    connectedCompleter.complete();
                  }
                case DeviceConnectionState.disconnected:
                  if (connectedCompleter.isCompleted &&
                      !disconnectCompleter.isCompleted) {
                    // Dropped after connecting — stale-bond scenario.
                    disconnectCompleter.completeError(
                      Exception('Connection dropped before pairing'),
                    );
                  }
                // If not yet connected: connectToDevice auto-retries;
                // do nothing and let it keep trying until timeout.
                default:
                  break;
              }
            },
            onError: (Object e) {
              if (!connectedCompleter.isCompleted) {
                connectedCompleter.completeError(e);
              } else if (!disconnectCompleter.isCompleted) {
                disconnectCompleter.completeError(e);
              }
            },
          );

      await connectedCompleter.future;
      await ble.discoverAllServices(deviceId);

      final vehicle = ref.read(availableVehiclesProvider).first;

      // Write a single probe byte to the app→device characteristic to trigger
      // Android bonding. Subscribing to the device→app characteristic does NOT
      // require bonding on this firmware — only writes do. The OS intercepts
      // the ATT_ERROR_INSUFFICIENT_AUTH response, shows the pairing dialog,
      // establishes the bond, and lets us retry. We loop until the write
      // succeeds (bond confirmed) or the connection drops (stale-bond: firmware
      // closed the link because it still had an old bond record).
      final rxChar = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: Uuid.parse(vehicle.bleServiceUuid),
        characteristicId: Uuid.parse(vehicle.bleAppToDeviceCharacteristicUuid),
      );

      dev.log(
        'Wizard: writing probe to trigger bonding',
        name: 'PairingWizard',
      );
      bool bondConfirmed = false;
      final deadline = DateTime.now().add(
        Duration(seconds: kBlePairingWindowSeconds),
      );
      while (DateTime.now().isBefore(deadline) && !bondConfirmed) {
        if (disconnectCompleter.isCompleted) break;
        try {
          // Race the write against the disconnect signal so we don't wait for
          // the GATT callback if the firmware drops the link (e.g. stale-bond
          // key mismatch after the Android pairing dialog is confirmed).
          // disconnectCompleter.future throws immediately once completed.
          await Future.any([
            ble.writeCharacteristicWithResponse(rxChar, value: []),
            disconnectCompleter.future,
          ]);
          bondConfirmed = true;
        } on Exception {
          if (disconnectCompleter.isCompleted) break;
          // Auth failure / transient error — bonding in progress. Back off.
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      // Rethrow any stale-bond disconnect that arrived during the retry loop.
      if (disconnectCompleter.isCompleted) {
        await disconnectCompleter.future;
      }

      if (!bondConfirmed) {
        throw TimeoutException(
          'Bonding did not complete within the pairing window',
          Duration(seconds: kBlePairingWindowSeconds),
        );
      }

      dev.log('Wizard: bond confirmed — saving config', name: 'PairingWizard');
      await connSub.cancel();
      connSub = null;

      await ref
          .read(pairedVehicleProvider.notifier)
          .pair(
            PairedVehicleConfig(
              vehicleId: vehicle.platformName,
              bleRemoteId: deviceId,
              transportPreference: TransportPreference.ble,
            ),
          );
      // AppEntryRouter will rebuild to show the dashboard.
    } on TimeoutException {
      await connSub?.cancel();
      _setError(
        'Pairing timed out. Make sure the pairing window is still open on '
        'the device and try again.',
      );
    } on Exception catch (e) {
      await connSub?.cancel();
      // If the connection dropped after connecting, treat it as a stale-bond
      // scenario (firmware cleared its entry; next attempt will succeed).
      if (e.toString().contains('Connection dropped before pairing')) {
        dev.log(
          'Stale bond detected — firmware cleared its entry, retry needed',
          name: 'PairingWizard',
        );
        if (mounted) {
          setState(() {
            _step = _Step.found;
            _staleBondWarning = true;
          });
        }
        return;
      }
      dev.log('Pairing failed: $e', name: 'PairingWizard');
      _setError('Pairing failed: $e');
    }
  }

  // ── HTTP pairing (debug only) ───────────────────────────────────────────────

  Future<void> _testHttpConnection() async {
    setState(() {
      _httpTesting = true;
      _httpTestResult = '';
    });
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 0;
    if (host.isEmpty || port == 0) {
      setState(() {
        _httpTesting = false;
        _httpTestResult = 'Enter a valid host and port.';
      });
      return;
    }
    try {
      await HttpCarTransport.testConnection(host, port);
      setState(() {
        _httpTesting = false;
        _httpTestResult = 'Connected ✓';
      });
    } on Exception catch (e) {
      setState(() {
        _httpTesting = false;
        _httpTestResult = 'Failed: $e';
      });
    }
  }

  Future<void> _openHttpPairingWindow() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 0;
    final t = HttpCarTransport(
      host: host,
      port: port,
      pollingIntervalMs: kDebugServerPollingIntervalMs,
    );
    try {
      await t.openPairingWindow();
      if (mounted) setState(() => _httpPairingWindowOpen = true);
    } on Exception catch (e) {
      _setError('Could not open pairing window: $e');
    } finally {
      t.dispose();
    }
  }

  Future<void> _pairHttp() async {
    setState(() => _step = _Step.pairing);
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 0;
    final t = HttpCarTransport(
      host: host,
      port: port,
      pollingIntervalMs: kDebugServerPollingIntervalMs,
    );
    try {
      await t.registerAsPairedPhone(ref.read(bleSourceDeviceIdProvider));
      t.dispose();

      final vehicle = ref.read(availableVehiclesProvider).first;
      await ref
          .read(pairedVehicleProvider.notifier)
          .pair(
            PairedVehicleConfig(
              vehicleId: vehicle.platformName,
              bleRemoteId: '',
              transportPreference: TransportPreference.http,
              httpHost: host,
              httpPort: port,
            ),
          );
    } on Exception catch (e) {
      t.dispose();
      _setError('HTTP pairing failed: $e');
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _step = _Step.error;
      _errorMessage = message;
    });
  }

  void _retry() {
    setState(() {
      _step = _Step.prompt;
      _foundDeviceId = null;
      _foundDeviceName = null;
      _errorMessage = '';
      _staleBondWarning = false;
      _httpMode = false;
      _httpPairingWindowOpen = false;
      _httpTestResult = '';
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair Your Vehicle')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            _Step.prompt => _buildPrompt(),
            _Step.scanning => _buildScanning(),
            _Step.found => _buildFound(),
            _Step.pairing => _buildPairing(),
            _Step.error => _buildError(),
          },
        ),
      ),
    );
  }

  Widget _buildPrompt() {
    if (kDebugMode && _httpMode) return _buildHttpForm();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.bluetooth_searching, size: 64),
        const SizedBox(height: 24),
        Text(
          'Hold the pairing button on your vehicle',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'The device will advertise for $kBleScanTimeoutSeconds seconds. '
          'Tap Start when ready.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _startScan,
          icon: const Icon(Icons.search),
          label: const Text('Start'),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => setState(() => _httpMode = true),
            child: const Text('Use HTTP instead (debug)'),
          ),
        ],
      ],
    );
  }

  Widget _buildScanning() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CircularProgressIndicator.adaptive(strokeWidth: 3),
        const SizedBox(height: 24),
        Text(
          'Looking for your vehicle…',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '$_remainingSeconds s remaining',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        OutlinedButton(
          onPressed: () {
            _stopScan();
            _retry();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildFound() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.bluetooth_connected, size: 64),
        const SizedBox(height: 24),
        Text(
          'Vehicle found',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (_foundDeviceName != null && _foundDeviceName!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            _foundDeviceName!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 4),
        Text(
          _foundDeviceId ?? '',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        ),
        if (_staleBondWarning) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your phone had previously paired with this vehicle, but '
                    'the vehicle was still remembering it. The vehicle has now '
                    'cleared the old pairing. Tap Pair again to complete the '
                    'process — you may see a second pairing prompt.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _pairBle,
          icon: const Icon(Icons.link),
          label: const Text('Pair'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _retry, child: const Text('Cancel')),
      ],
    );
  }

  Widget _buildPairing() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CircularProgressIndicator.adaptive(strokeWidth: 3),
        SizedBox(height: 24),
        Text('Pairing…', textAlign: TextAlign.center),
        SizedBox(height: 8),
        Text(
          'Confirm the pairing request on your phone if prompted.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.error_outline,
          size: 64,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 24),
        Text(
          'Pairing failed',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }

  // ── HTTP form (debug only) ──────────────────────────────────────────────────

  Widget _buildHttpForm() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'HTTP Debug Transport',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Enter the address of the device HTTP server.'),
          const SizedBox(height: 20),
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Host',
              hintText: '192.168.1.100',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'Port',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _httpTesting ? null : _testHttpConnection,
            child: _httpTesting
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Text('Test Connection'),
          ),
          if (_httpTestResult.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _httpTestResult,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _openHttpPairingWindow,
            child: Text(
              _httpPairingWindowOpen
                  ? 'Pairing window open ✓'
                  : 'Open Pairing Window on Device',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _httpPairingWindowOpen ? _pairHttp : null,
            icon: const Icon(Icons.link),
            label: const Text('Pair'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() => _httpMode = false),
            child: const Text('Back to BLE'),
          ),
        ],
      ),
    );
  }
}
