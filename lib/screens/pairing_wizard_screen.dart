import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:open_car_app/providers/ble_pairing_connect.dart';
import 'package:open_car_app/providers/can_access_provider.dart';
import 'package:open_car_app/providers/phone_access_provider.dart';
import 'package:open_car_app/providers/ble_provider.dart';
import 'package:open_car_app/cars/virtual_car/constants.g.dart';
import 'package:open_car_app/config/mqtt_broker_config.g.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/ble_source_device_id_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';
import 'package:open_car_app/screens/help_screen.dart';
import 'package:open_car_app/screens/theme_gallery_screen.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_theme.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/theme/vehicle_skin.dart';
import 'package:open_car_app/transport/ble_fragmentation.dart';
import 'package:open_car_app/transport/http_transport.dart';
import 'package:open_car_app/generated/opencar/core/v1/core.pb.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/widgets/can_read_write_approval_dialog.dart';
import 'package:open_car_app/widgets/wizard_frame.dart';
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

  /// Paired; waiting for the device to report what still needs setting up.
  connecting,

  /// The CAN read-write approval. Can be skipped.
  approval,

  /// Fatal error; user can retry.
  error,
}

// ── Screen ────────────────────────────────────────────────────────────────────

class PairingWizardScreen extends ConsumerStatefulWidget {
  const PairingWizardScreen({super.key, this.addVehicle = false});

  /// Pushed over the app to add another vehicle: it has a close button and
  /// its own heading, and pops when done. The first run has neither, because
  /// there is nothing to go back to.
  final bool addVehicle;

  /// The wizard pushed over the app to add another vehicle.
  static Route<void> addVehicleRoute() => MaterialPageRoute<void>(
    builder: (_) => const PairingWizardScreen(addVehicle: true),
  );

  @override
  ConsumerState<PairingWizardScreen> createState() =>
      _PairingWizardScreenState();
}

class _PairingWizardScreenState extends ConsumerState<PairingWizardScreen> {
  _Step _step = _Step.prompt;
  String? _foundDeviceId;
  String? _foundDeviceName;
  String _errorMessage = '';
  String _errorTitle = _pairingFailedTitle;
  WizardStage _errorStage = WizardStage.pair;
  bool _staleBondWarning = false;

  static const _pairingFailedTitle = 'Pairing failed';

  /// How long to wait for the device to report its CAN access after pairing.
  /// It repeats that state every few seconds, once the connection is up.
  static const _setupWaitSeconds = 20;

  // Set-up steps
  bool _paired = false;
  bool _finished = false;
  bool _acknowledged = false;
  bool _approving = false;
  String? _approvalError;
  Timer? _setupTimer;

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
    _setupTimer?.cancel();
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
      _setError(
        'Bluetooth permission denied. Grant it in app settings.',
        stage: WizardStage.find,
      );
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
        // A device that already has a paired phone hides from phones it
        // doesn't know (reinstalled app, new phone): point to the recovery.
        _setError(
          'No device found. Make sure the device is in pairing mode and try '
          'again. If this phone or app was paired with it before, the device '
          'may no longer recognise it: see Help to reset its paired phones.',
          title: 'No vehicle found',
          stage: WizardStage.find,
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

      connSub =
          connectForPairing(
            ble,
            id: deviceId,
            window: Duration(seconds: kBlePairingWindowSeconds),
          ).listen(
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
                // Not yet connected: connectForPairing swallows these and
                // retries the attempt itself.
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

      // connectForPairing restarts attempts that end or go quiet (Android has
      // been seen abandoning one: client registered, then closed at once, with
      // no further update); this timeout is the backstop for the whole window.
      await connectedCompleter.future.timeout(
        Duration(seconds: kBlePairingWindowSeconds),
      );
      await ble.requestMtu(deviceId: deviceId, mtu: kBleAttMtu);
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

      dev.log(
        'Wizard: bond confirmed — waiting for platform ID',
        name: 'PairingWizard',
      );

      final txChar = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: Uuid.parse(vehicle.bleServiceUuid),
        characteristicId: Uuid.parse(vehicle.bleDeviceToAppCharacteristicUuid),
      );

      // Notifications are chunks, like on the dashboard's transport.
      final reassembler = BleReassembler(
        onDrop: (reason) =>
            dev.log('Dropped BLE chunk: ${reason.name}', name: 'PairingWizard'),
      );
      final firstMsgBytes = await ble
          .subscribeToCharacteristic(txChar)
          .map(reassembler.push)
          .firstWhere((message) => message != null)
          // A state update sent before the subscription is lost, so this can
          // take a full publish interval (5 s on the virtual car).
          .timeout(const Duration(seconds: 15));
      final msg = DeviceToApp.fromBuffer(firstMsgBytes!);

      final allVehicles = ref.read(availableVehiclesProvider);
      final actualVehicle = allVehicles.firstWhere(
        (v) => v.platformId == msg.platformId,
        orElse: () => throw Exception(
          'Unsupported vehicle platform ID: ${msg.platformId}',
        ),
      );

      dev.log(
        'Wizard: platform ID validated as ${actualVehicle.platformName} — saving config',
        name: 'PairingWizard',
      );
      await connSub.cancel();
      connSub = null;

      await _savePairing(
        PairedVehicleConfig(
          id: newPairedVehicleId(),
          vehicleId: actualVehicle.platformName,
          bleRemoteId: deviceId,
          transportPreference: TransportPreference.ble,
        ),
      );
    } on TimeoutException {
      await connSub?.cancel();
      _setError(
        'Make sure the pairing window is still open on the device and try '
        'again.',
        title: 'Pairing timed out',
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
      _setError('Could not open pairing window: $e', stage: WizardStage.find);
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

      // Messages without a platform ID (e.g. a bare command response) can't
      // identify the vehicle; wait for one that does.
      final msg = await t.messages
          .firstWhere((m) => m.platformId != 0)
          .timeout(const Duration(seconds: 5));
      final allVehicles = ref.read(availableVehiclesProvider);
      final actualVehicle = allVehicles.firstWhere(
        (v) => v.platformId == msg.platformId,
        orElse: () => throw Exception(
          'Unsupported vehicle platform ID: ${msg.platformId}',
        ),
      );

      await _savePairing(
        PairedVehicleConfig(
          id: newPairedVehicleId(),
          vehicleId: actualVehicle.platformName,
          bleRemoteId: '',
          transportPreference: TransportPreference.http,
          httpHost: host,
          httpPort: port,
        ),
      );
    } catch (e) {
      _setError('HTTP pairing failed: $e');
    } finally {
      t.dispose();
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _setError(
    String message, {
    String title = _pairingFailedTitle,
    WizardStage stage = WizardStage.pair,
  }) {
    if (!mounted) return;
    setState(() {
      _step = _Step.error;
      _errorMessage = message;
      _errorTitle = title;
      _errorStage = stage;
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

  // ── Set-up steps ────────────────────────────────────────────────────────────

  /// Saves the pairing and moves on to the set-up steps.
  Future<void> _savePairing(PairedVehicleConfig config) async {
    // Before pairing, so the router never swaps the wizard for the dashboard.
    if (!widget.addVehicle) {
      ref.read(wizardSetupPendingProvider.notifier).begin();
    }
    await ref.read(pairedVehiclesProvider.notifier).pair(config);
    if (!mounted) return;

    setState(() {
      _paired = true;
      _step = _Step.connecting;
    });
    ref.listenManual(canAccessStateProvider, (_, _) => _onAccessChanged());
    ref.listenManual(phoneAccessStateProvider, (_, _) => _onAccessChanged());
    _setupTimer = Timer(const Duration(seconds: _setupWaitSeconds), () {
      if (_step == _Step.connecting) _finishSetup();
    });
    _onAccessChanged();
  }

  /// Decides what the approval step does, from what the device reports on the
  /// connection the app has just opened.
  void _onAccessChanged() {
    if (_finished || _approving) return;
    if (_step != _Step.connecting && _step != _Step.approval) return;

    // The device would refuse this phone the approval.
    final phone = ref.read(phoneAccessStateProvider);
    if (phone != null && isOutrankedByValidatedPhone(phone)) {
      _finishSetup();
      return;
    }

    if (_step != _Step.connecting) return;
    final access = ref.read(canAccessStateProvider);
    if (access == null) return;
    if (canAccessNeedsApproval(access)) {
      _setupTimer?.cancel();
      setState(() => _step = _Step.approval);
    } else if (access.approval ==
            CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_APPROVED ||
        access.approval ==
            CanReadWriteApproval.CAN_READ_WRITE_APPROVAL_AWAITING_CAR) {
      _finishSetup();
    }
    // Otherwise the car isn't identified yet: wait, up to the timer. The
    // dashboard's banner offers the approval once it is.
  }

  Future<void> _approve() async {
    setState(() {
      _approving = true;
      _approvalError = null;
    });
    try {
      await ref.read(canAccessActionsProvider).setApproval(true);
      if (mounted) _finishSetup();
    } catch (e) {
      if (mounted) {
        setState(() {
          _approving = false;
          _approvalError = '$e';
        });
      }
    }
  }

  /// The approval is done or skipped. The phone is validated from the
  /// dashboard, which offers it next.
  void _finishSetup() {
    if (_finished) return;
    _finished = true;
    _setupTimer?.cancel();
    if (widget.addVehicle) {
      Navigator.of(context).pop();
    } else {
      // The router rebuilds to show the dashboard.
      ref.read(wizardSetupPendingProvider.notifier).finish();
    }
  }

  void _close() {
    if (_paired) {
      _finishSetup();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  WizardStage get _stage => switch (_step) {
    _Step.prompt || _Step.scanning => WizardStage.find,
    _Step.found || _Step.pairing => WizardStage.pair,
    _Step.connecting || _Step.approval => WizardStage.setUp,
    _Step.error => _errorStage,
  };

  void _openHelp() => HelpScreen.open(context);

  WizardFrame _frame({
    required String title,
    Widget? medallion,
    String? body,
    List<Widget> content = const [],
    List<Widget> actions = const [],
  }) => WizardFrame(
    heading: widget.addVehicle ? 'Add a vehicle' : 'Pair your vehicle',
    // Pairing can't be abandoned halfway: it would still save the vehicle.
    onClose: widget.addVehicle && _step != _Step.pairing ? _close : null,
    onHelp: _openHelp,
    stage: _stage,
    medallion: medallion,
    title: title,
    body: body,
    content: content,
    actions: actions,
  );

  @override
  Widget build(BuildContext context) {
    final page = PopScope(
      canPop: !(widget.addVehicle && _step == _Step.pairing),
      child: switch (_step) {
        _Step.prompt => _buildPrompt(),
        _Step.scanning => _buildScanning(),
        _Step.found => _buildFound(),
        _Step.pairing => _buildPairing(),
        _Step.connecting => _buildConnecting(),
        _Step.approval => _buildApproval(),
        _Step.error => _buildError(),
      },
    );

    // Added over a paired vehicle, the app's theme is that vehicle's skin.
    if (widget.addVehicle && !_paired) {
      return Theme(
        data: buildAppTheme(defaultSkin, Theme.of(context).brightness),
        child: page,
      );
    }
    return page;
  }

  Widget _buildPrompt() {
    if (kDebugMode && _httpMode) return _buildHttpForm();

    return _frame(
      medallion: const WizardMedallion(icon: Symbols.bluetooth_searching),
      title: 'Put your device in pairing mode',
      body:
          'A device with no paired phone yet is in pairing mode for '
          '${HelpScreen.duration(kBleFirstSetupPairingWindowSeconds)} after it '
          'is powered on. If yours has a pairing button, hold it. Then tap '
          'Start: the app searches for $kBleScanTimeoutSeconds seconds.',
      actions: [
        WizardPrimaryButton(label: 'Start', onPressed: _startScan),
        if (kDebugMode) ...[
          WizardSecondaryButton(
            label: 'Use HTTP instead (debug)',
            onPressed: () => setState(() => _httpMode = true),
          ),
          WizardSecondaryButton(
            label: 'Theme gallery (debug)',
            onPressed: () => ThemeGalleryScreen.open(context),
          ),
        ],
      ],
    );
  }

  Widget _buildScanning() {
    return _frame(
      medallion: const WizardMedallion(icon: Symbols.bluetooth, rings: true),
      title: 'Looking for your vehicle…',
      body: '$_remainingSeconds s remaining',
      actions: [
        WizardSecondaryButton(
          label: 'Cancel',
          onPressed: () {
            _stopScan();
            _retry();
          },
        ),
      ],
    );
  }

  /// The device advertises its name only in pairing mode, so one found
  /// without it is outside pairing mode: Android still reports it from the
  /// services it cached while this phone was paired. It only accepts this
  /// phone if it still has its bond (e.g. the app was reinstalled but Android
  /// kept the pairing); otherwise its paired phones have to be reset.
  bool get _foundOutsidePairingMode =>
      _foundDeviceName == null || _foundDeviceName!.isEmpty;

  /// The note on the found step, if there is one to show.
  String? get _foundNote {
    if (_staleBondWarning && _foundOutsidePairingMode) {
      // The device has an old bond for this phone and, outside pairing
      // mode, doesn't clear it: Pair again would fail the same way.
      return 'The vehicle still remembers an old pairing with this phone and '
          'is not in pairing mode, so it can\'t pair again. Reset its paired '
          'phones (see Help), then tap Pair again.';
    }
    if (_staleBondWarning) {
      return 'Your phone had paired with this vehicle before, and the vehicle '
          'still remembered it. The old pairing is cleared now. Tap Pair '
          'again to finish; you may see a second pairing prompt.';
    }
    if (_foundOutsidePairingMode) {
      return 'This vehicle is not in pairing mode. If this phone is still '
          'paired with it, Pair works. Otherwise put it in pairing mode first '
          '(see Help).';
    }
    return null;
  }

  Widget _buildFound() {
    final note = _foundNote;
    return _frame(
      medallion: const WizardMedallion(icon: Symbols.bluetooth_connected),
      title: 'Vehicle found',
      body: 'Check that this is your vehicle, then pair.',
      content: [
        _DeviceCard(name: _foundDeviceName, id: _foundDeviceId ?? ''),
        if (note != null) WizardNote(note),
        if (_foundOutsidePairingMode)
          Center(
            child: TextButton.icon(
              onPressed: _openHelp,
              icon: const Icon(Symbols.help),
              label: const Text('Help'),
            ),
          ),
      ],
      actions: [
        WizardPrimaryButton(label: 'Pair', onPressed: _pairBle),
        WizardSecondaryButton(label: 'Cancel', onPressed: _retry),
      ],
    );
  }

  Widget _buildPairing() {
    return _frame(
      medallion: const WizardMedallion(icon: Symbols.bluetooth, rings: true),
      title: 'Pairing…',
      body: 'Confirm the pairing request on your phone if prompted.',
    );
  }

  Widget _buildConnecting() {
    return _frame(
      medallion: const WizardMedallion(
        icon: Symbols.bluetooth_connected,
        rings: true,
      ),
      title: 'Connecting to your vehicle…',
      body: 'Paired. You can also finish setting it up later in settings.',
      actions: [
        WizardSecondaryButton(label: 'Not now', onPressed: _finishSetup),
      ],
    );
  }

  Widget _buildApproval() {
    return _frame(
      title: 'Allow control of this car?',
      body:
          'Read this before letting the device send commands. You can also do '
          'it later in settings.',
      content: [
        _ApprovalCard(
          acknowledged: _acknowledged,
          onChanged: _approving
              ? null
              : (value) => setState(() => _acknowledged = value ?? false),
          error: _approvalError,
        ),
      ],
      actions: [
        WizardPrimaryButton(
          label: 'Allow control',
          onPressed: _acknowledged && !_approving ? _approve : null,
        ),
        WizardSecondaryButton(
          label: 'Not now',
          onPressed: _approving ? null : _finishSetup,
        ),
      ],
    );
  }

  Widget _buildError() {
    return _frame(
      medallion: const WizardMedallion(icon: Symbols.error, danger: true),
      title: _errorTitle,
      body: _errorMessage,
      actions: [
        WizardPrimaryButton(label: 'Try again', onPressed: _retry),
        WizardSecondaryButton(label: 'Help', onPressed: _openHelp),
      ],
    );
  }

  // ── HTTP form (debug only) ──────────────────────────────────────────────────

  Widget _buildHttpForm() {
    return _frame(
      title: 'HTTP Debug Transport',
      body: 'Enter the address of the device HTTP server.',
      content: [
        TextField(
          controller: _hostController,
          decoration: const InputDecoration(
            labelText: 'Host',
            hintText: '192.168.1.100',
          ),
          keyboardType: TextInputType.url,
        ),
        TextField(
          controller: _portController,
          decoration: const InputDecoration(labelText: 'Port'),
          keyboardType: TextInputType.number,
        ),
        OutlinedButton(
          onPressed: _httpTesting ? null : _testHttpConnection,
          child: _httpTesting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                )
              : const Text('Test Connection'),
        ),
        if (_httpTestResult.isNotEmpty)
          Text(_httpTestResult, textAlign: TextAlign.center),
        OutlinedButton(
          onPressed: _openHttpPairingWindow,
          child: Text(
            _httpPairingWindowOpen
                ? 'Pairing window open ✓'
                : 'Open Pairing Window on Device',
          ),
        ),
      ],
      actions: [
        WizardPrimaryButton(
          label: 'Pair',
          onPressed: _httpPairingWindowOpen ? _pairHttp : null,
        ),
        WizardSecondaryButton(
          label: 'Back to BLE',
          onPressed: () => setState(() => _httpMode = false),
        ),
      ],
    );
  }
}

/// The device the scan found. One outside pairing mode has no name.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.name, required this.id});

  final String? name;
  final String id;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final name = this.name;
    return WizardCard(
      child: Row(
        spacing: 12,
        children: [
          Icon(Symbols.bluetooth, color: tokens.accent),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name != null && name.isNotEmpty)
                  Text(name, style: AppTextStyles.wizardButton),
                Text(
                  id,
                  style: AppTextStyles.caption.copyWith(
                    color: tokens.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The risks of approving control, and the acknowledgement.
class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.acknowledged,
    required this.onChanged,
    required this.error,
  });

  final bool acknowledged;
  final ValueChanged<bool?>? onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final error = this.error;
    return WizardCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultTextStyle.merge(
            style: AppTextStyles.wizardNote.copyWith(
              color: tokens.textSecondary,
            ),
            child: const CanReadWriteRisksText(),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: acknowledged,
            onChanged: onChanged,
            title: const Text('I understand the risks'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error,
                style: AppTextStyles.wizardNote.copyWith(color: tokens.danger),
              ),
            ),
        ],
      ),
    );
  }
}
