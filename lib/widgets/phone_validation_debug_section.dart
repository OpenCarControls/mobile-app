import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/models/paired_phone.dart';
import 'package:open_car_app/providers/phone_access_provider.dart';

/// Debug-only way to run a phone validation until the real flow exists. Show it
/// behind `kDebugMode`. Method identifiers are shown as the device sends them.
class PhoneValidationDebugSection extends ConsumerStatefulWidget {
  const PhoneValidationDebugSection({super.key});

  @override
  ConsumerState<PhoneValidationDebugSection> createState() =>
      _PhoneValidationDebugSectionState();
}

class _PhoneValidationDebugSectionState
    extends ConsumerState<PhoneValidationDebugSection> {
  final _code = TextEditingController();
  List<PhoneValidationMethod>? _methods;
  List<PairedPhoneInfo>? _phones;
  bool _sending = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(PhoneValidationActions) action,
  ) async {
    setState(() => _sending = true);
    try {
      await action(ref.read(phoneValidationActionsProvider));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submitCode() => _run((actions) async {
    final code = _code.text;
    _code.clear();
    await actions.submitCode(code);
  });

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(phoneAccessStateProvider);
    if (access == null) {
      return const ListTile(
        leading: Icon(Icons.bug_report_outlined),
        title: Text('Phone validation (debug)'),
        subtitle: Text('Not reported: connect over Bluetooth.'),
      );
    }

    final session = access.hasValidation() ? access.validation : null;
    final running =
        session?.status ==
        PhoneValidationStatus.PHONE_VALIDATION_STATUS_IN_PROGRESS;
    final takesCode =
        running &&
        session?.kind ==
            PhoneValidationMethodKind.PHONE_VALIDATION_METHOD_KIND_CODE_ENTRY;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Phone validation (debug)'),
          subtitle: Text(
            'Trust: ${access.trust.name}\n'
            'Car has a validated phone: ${access.carHasValidatedPhone}'
            '${session == null ? '' : '\n${_sessionText(session)}'}',
          ),
        ),
        if (takesCode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: session!.codeLength,
              decoration: InputDecoration(
                labelText: 'Code (${session.attemptsLeft} attempts left)',
              ),
              onSubmitted: _sending ? null : (_) => _submitCode(),
            ),
          ),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          children: [
            if (takesCode)
              TextButton(
                onPressed: _sending ? null : _submitCode,
                child: const Text('Submit code'),
              ),
            if (running)
              TextButton(
                onPressed: _sending ? null : () => _run((a) => a.cancel()),
                child: const Text('Cancel session'),
              ),
            TextButton(
              onPressed: _sending
                  ? null
                  : () => _run((a) async {
                      final methods = await a.listMethods();
                      if (mounted) setState(() => _methods = methods);
                    }),
              child: const Text('List methods'),
            ),
            TextButton(
              onPressed: _sending
                  ? null
                  : () => _run((a) async {
                      final phones = await a.listPairedPhones();
                      if (mounted) setState(() => _phones = phones);
                    }),
              child: const Text('List phones'),
            ),
          ],
        ),
        for (final method in _methods ?? const <PhoneValidationMethod>[])
          ListTile(
            dense: true,
            title: Text(method.methodId),
            subtitle: Text(
              '${method.kind.name}'
              '${method.needsApproval ? ', needs the approval' : ''}',
            ),
            trailing: const Icon(Icons.play_arrow),
            enabled: method.available && !_sending,
            onTap: () => _run((a) => a.start(method.methodId)),
          ),
        for (final phone in _phones ?? const <PairedPhoneInfo>[])
          ListTile(
            dense: true,
            title: Text(
              '${_hex(phone.deviceId)}${phone.isThisPhone ? ' (this phone)' : ''}',
            ),
            subtitle: Text(phone.trust.name),
          ),
      ],
    );
  }

  String _sessionText(PhoneValidationSession session) =>
      'Session: ${session.methodId}, ${session.status.name}, '
      '${session.expiresInS} s left, cooldown ${session.cooldownS} s';

  String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
