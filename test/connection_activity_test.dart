import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:open_car_app/config/connection_activity_config.dart';
import 'package:open_car_app/config/paired_vehicle_config.dart';
import 'package:open_car_app/models/connection_activity.dart';
import 'package:open_car_app/providers/connection_activity_provider.dart';
import 'package:open_car_app/providers/paired_vehicle_provider.dart';

const _vehicle = PairedVehicleConfig(
  vehicleId: 'egmp',
  bleRemoteId: 'AA:BB:CC:DD:EE:FF',
  transportPreference: TransportPreference.ble,
);

final _time = DateTime.utc(2026, 11, 9, 14, 21);

ProviderContainer _container({
  PairedVehicleConfig? vehicle = _vehicle,
  ConnectionActivityLogs logs = const {},
}) {
  final container = ProviderContainer(
    overrides: [
      initialPairedVehiclesProvider.overrideWithValue(
        PairedVehicles.of(vehicle),
      ),
      initialConnectionActivityProvider.overrideWithValue(logs),
    ],
  );
  addTearDown(container.dispose);
  container.read(connectionActivityLogsProvider.notifier).now = () => _time;
  return container;
}

ConnectionActivityNotifier _log(ProviderContainer container) =>
    container.read(connectionActivityLogsProvider.notifier);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('entry text', () {
    test('connection changes are in plain words', () {
      String line(ConnectionChange change) {
        final entry = ConnectionChangeEntry(_time, change);
        return [entry.title, ?entry.detail].join(' · ');
      }

      expect(line(ConnectionChange.bluetoothConnected), 'Bluetooth connected');
      expect(
        line(ConnectionChange.bluetoothLost),
        'Bluetooth link lost · Switched to remote',
      );
      expect(line(ConnectionChange.remoteConnected), 'Remote connected');
    });

    test('command outcomes are in plain words', () {
      String detail(CommandOutcome outcome) =>
          CommandEntry(_time, command: 'Unlock doors', outcome: outcome).detail;

      expect(detail(CommandOutcome.done), 'Done');
      expect(detail(CommandOutcome.noAnswer), 'No answer from the vehicle');
      expect(detail(CommandOutcome.vehicleUnavailable), 'Vehicle unavailable');
      expect(detail(CommandOutcome.needsApproval), 'Needs approval');
      expect(detail(CommandOutcome.notValidated), 'Phone not validated');
      expect(detail(CommandOutcome.failed), 'Failed');
    });

    test('says when a command was sent remotely', () {
      final entry = CommandEntry(
        _time,
        command: 'Lock doors',
        outcome: CommandOutcome.done,
        sentRemotely: true,
      );
      expect(entry.title, 'Lock doors');
      expect(entry.detail, 'Done · sent remotely');
    });

    test('only an unsuccessful command is a failure', () {
      for (final outcome in CommandOutcome.values) {
        expect(
          CommandEntry(_time, command: 'Lock', outcome: outcome).isFailure,
          outcome != CommandOutcome.done,
          reason: outcome.name,
        );
      }
      expect(
        ConnectionChangeEntry(_time, ConnectionChange.bluetoothLost).isFailure,
        isFalse,
      );
    });
  });

  group('recording', () {
    test('lists the newest entry first', () {
      final container = _container();
      _log(container).recordConnection(ConnectionChange.bluetoothConnected);
      _log(container).recordCommand('Lock doors', CommandOutcome.done);

      expect(container.read(connectionActivityProvider).map((e) => e.title), [
        'Lock doors',
        'Bluetooth connected',
      ]);
    });

    test('keeps only the newest entries', () {
      final container = _container();
      for (var i = 0; i <= kConnectionActivityMaxEntries; i++) {
        _log(container).recordCommand('Command $i', CommandOutcome.done);
      }

      final entries = container.read(connectionActivityProvider);
      expect(entries, hasLength(kConnectionActivityMaxEntries));
      expect(entries.first.title, 'Command $kConnectionActivityMaxEntries');
      expect(entries.last.title, 'Command 1');
    });

    test('keeps each vehicle apart', () {
      final other = ConnectionChangeEntry(
        _time,
        ConnectionChange.remoteConnected,
      );
      final container = _container(
        logs: {
          'other': [other],
        },
      );
      _log(container).recordCommand('Lock doors', CommandOutcome.done);

      expect(container.read(connectionActivityLogsProvider)['other'], [other]);
      expect(
        container.read(connectionActivityProvider).single.title,
        'Lock doors',
      );
    });

    test('records nothing without a paired vehicle', () {
      final container = _container(vehicle: null);
      _log(container).recordCommand('Lock doors', CommandOutcome.done);

      expect(container.read(connectionActivityLogsProvider), isEmpty);
      expect(container.read(connectionActivityProvider), isEmpty);
    });
  });

  group('storage', () {
    test('survives an app restart', () async {
      final container = _container();
      _log(container).recordConnection(ConnectionChange.bluetoothLost);
      _log(container).recordCommand(
        'Lock doors',
        CommandOutcome.noAnswer,
        sentRemotely: true,
      );
      await pumpEventQueue();

      final entries = (await loadConnectionActivity())[_vehicle.storageKey]!;
      expect(entries, hasLength(2));
      final command = entries[0] as CommandEntry;
      expect(command.time.isUtc, isFalse);
      expect(command.time.isAtSameMomentAs(_time), isTrue);
      expect(command.command, 'Lock doors');
      expect(command.outcome, CommandOutcome.noAnswer);
      expect(command.sentRemotely, isTrue);
      expect(
        (entries[1] as ConnectionChangeEntry).change,
        ConnectionChange.bluetoothLost,
      );
    });

    test('stores no identifiers', () async {
      final container = _container();
      _log(container).recordConnection(ConnectionChange.bluetoothConnected);
      _log(container).recordCommand('Lock doors', CommandOutcome.done);
      await pumpEventQueue();

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('connection_activity/egmp')!;
      expect(raw, isNot(contains(_vehicle.bleRemoteId)));
      expect(
        {for (final e in jsonDecode(raw) as List) ...(e as Map).keys},
        {'time', 'change', 'command', 'outcome', 'sentRemotely'},
      );
    });

    test('skips an entry it cannot read', () async {
      SharedPreferences.setMockInitialValues({
        'connection_activity/egmp': jsonEncode([
          {'time': _time.toIso8601String(), 'change': 'somethingNew'},
          {'time': _time.toIso8601String(), 'change': 'remoteConnected'},
          'not an entry',
        ]),
      });

      final entries = (await loadConnectionActivity())['egmp']!;
      expect(entries.single.title, 'Remote connected');
    });

    test('ignores a corrupt log', () async {
      SharedPreferences.setMockInitialValues({
        'connection_activity/egmp': '{not json',
        'connection_activity/other': '{"not": "a list"}',
      });

      expect(await loadConnectionActivity(), isEmpty);
    });

    test('unpairing deletes the vehicle\'s log', () async {
      final container = _container();
      _log(container).recordCommand('Lock doors', CommandOutcome.done);
      await pumpEventQueue();

      await container.read(pairedVehiclesProvider.notifier).unpair();

      expect(container.read(connectionActivityLogsProvider), isEmpty);
      expect(await loadConnectionActivity(), isEmpty);
    });
  });
}
