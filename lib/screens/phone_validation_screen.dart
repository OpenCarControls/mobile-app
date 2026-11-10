import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

// Transport constants are identical in every vehicle's constants.g.dart.
import 'package:open_car_app/cars/virtual_car/constants.g.dart'
    show kBlePhoneValidationSessionSeconds;
import 'package:open_car_app/generated/opencar/core/v1/system.pb.dart';
import 'package:open_car_app/models/phone_validation_text.dart';
import 'package:open_car_app/providers/can_access_provider.dart';
import 'package:open_car_app/providers/phone_access_provider.dart';
import 'package:open_car_app/providers/selected_vehicle_provider.dart';
import 'package:open_car_app/providers/vehicle_state_provider.dart';
import 'package:open_car_app/screens/help_screen.dart';
import 'package:open_car_app/theme/app_text_styles.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/can_read_write_approval_dialog.dart';
import 'package:open_car_app/widgets/wizard_frame.dart';

const _codeEntry =
    PhoneValidationMethodKind.PHONE_VALIDATION_METHOD_KIND_CODE_ENTRY;

/// How often the method list is read again while it is on screen, in seconds:
/// the device doesn't announce that a method became available.
const _methodsRefreshSeconds = 3;

const _cantReachDevice = "Couldn't reach the device. Try again.";

enum _Stage {
  methods,
  session,
  validated,
  tooManyWrongCodes,
  timedOut,
  otherPhone,
}

/// Proves in the car that this phone is the owner's. See "Phone validation" in
/// `docs/ui-screens.md`.
class PhoneValidationScreen extends ConsumerStatefulWidget {
  const PhoneValidationScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const PhoneValidationScreen(),
    ),
  );

  @override
  ConsumerState<PhoneValidationScreen> createState() =>
      _PhoneValidationScreenState();
}

class _PhoneValidationScreenState extends ConsumerState<PhoneValidationScreen> {
  _Stage _stage = _Stage.methods;

  List<PhoneValidationMethod>? _methods;
  bool _methodsFailed = false;
  bool _listing = false;
  int _secondsSinceList = 0;

  PhoneValidationSession? _session;
  String? _methodId;

  /// Local countdowns between the device's reports.
  int _secondsLeft = 0;
  int _cooldownLeft = 0;

  /// A command is on its way. Its answer decides what happens next, so what
  /// the device reports meanwhile is ignored.
  bool _busy = false;

  String _digits = '';
  bool _wrongCode = false;
  String? _error;

  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    // A session left running keeps going. One that has ended isn't news: the
    // device reports it for a while after it ends.
    final running = _runningSession(ref.read(phoneAccessStateProvider));
    if (running != null) {
      _show(running);
    } else {
      unawaited(_readMethods());
    }
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  PhoneValidationSession? _sessionOf(PhoneAccessState? access) =>
      access != null && access.hasValidation() ? access.validation : null;

  PhoneValidationSession? _runningSession(PhoneAccessState? access) {
    final session = _sessionOf(access);
    return session?.status ==
            PhoneValidationStatus.PHONE_VALIDATION_STATUS_IN_PROGRESS
        ? session
        : null;
  }

  void _onTick() {
    switch (_stage) {
      case _Stage.session when _secondsLeft > 0:
        setState(() => _secondsLeft--);
      case _Stage.tooManyWrongCodes when _cooldownLeft > 0:
        setState(() => _cooldownLeft--);
      case _Stage.methods:
        if (++_secondsSinceList >= _methodsRefreshSeconds) {
          unawaited(_readMethods());
        }
      default:
    }
  }

  Future<void> _readMethods() async {
    _secondsSinceList = 0;
    if (_listing) return;
    _listing = true;
    try {
      final methods = await ref
          .read(phoneValidationActionsProvider)
          .listMethods();
      if (mounted) {
        setState(() {
          _methods = methods;
          _methodsFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _methodsFailed = true);
    } finally {
      _listing = false;
    }
  }

  void _onAccessChanged(PhoneAccessState? access) {
    if (_busy) return;
    switch (_stage) {
      case _Stage.methods:
        final running = _runningSession(access);
        if (running != null) setState(() => _show(running));
      case _Stage.session:
        final session = _sessionOf(access);
        // Gone: the connection changed, or the device stopped reporting it.
        setState(() => session == null ? _backToMethods() : _show(session));
      default:
    }
  }

  /// Moves to where [session] stands. Call inside setState, or before the
  /// first build.
  void _show(PhoneValidationSession session) {
    _methodId = session.methodId;
    switch (session.status) {
      case PhoneValidationStatus.PHONE_VALIDATION_STATUS_IN_PROGRESS:
        final wasRunning = _stage == _Stage.session;
        _stage = _Stage.session;
        _session = session;
        // The device rounds up: don't let its reports make the time jump.
        if (!wasRunning || (session.expiresInS - _secondsLeft).abs() > 1) {
          _secondsLeft = session.expiresInS;
        }
      case PhoneValidationStatus.PHONE_VALIDATION_STATUS_SUCCEEDED:
        _stage = _Stage.validated;
      case PhoneValidationStatus.PHONE_VALIDATION_STATUS_FAILED:
        _cooldownLeft = session.cooldownS;
        _stage = _Stage.tooManyWrongCodes;
      case PhoneValidationStatus.PHONE_VALIDATION_STATUS_TIMED_OUT:
        _stage = _Stage.timedOut;
      default:
        _backToMethods();
    }
  }

  void _backToMethods() {
    _stage = _Stage.methods;
    _session = null;
    _digits = '';
    _wrongCode = false;
    unawaited(_readMethods());
  }

  void _onRefused(CommandRejectedException refused) {
    switch (refused.validationRefusal?.reason) {
      case PhoneValidationRefusalReason
          .PHONE_VALIDATION_REFUSAL_REASON_OTHER_PHONE_VALIDATING:
        _stage = _Stage.otherPhone;
      case PhoneValidationRefusalReason
          .PHONE_VALIDATION_REFUSAL_REASON_COOLING_DOWN:
        _cooldownLeft = refused.validationRefusal!.cooldownS;
        _stage = _Stage.tooManyWrongCodes;
      case PhoneValidationRefusalReason
          .PHONE_VALIDATION_REFUSAL_REASON_NO_SESSION:
        _error = 'This validation has ended.';
        _backToMethods();
      default:
        _error = "This can't start right now. Check the car and try again.";
        _backToMethods();
    }
  }

  /// Runs a command that starts or answers a session.
  Future<void> _send(
    Future<PhoneValidationSession> Function(PhoneValidationActions) command, {
    void Function(PhoneValidationSession)? onWrongCode,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await command(ref.read(phoneValidationActionsProvider));
      if (mounted) setState(() => _show(session));
    } on CommandRejectedException catch (e) {
      if (!mounted) return;
      setState(() {
        final session = e.validationSession;
        if (session == null) {
          _onRefused(e);
        } else {
          onWrongCode?.call(session);
          _show(session);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _digits = '';
          _error = _cantReachDevice;
        });
      }
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _start(String methodId) {
    _methodId = methodId;
    _digits = '';
    _wrongCode = false;
    return _send((actions) => actions.start(methodId));
  }

  Future<void> _startAgain() => _start(_methodId!);

  Future<void> _submit() => _send(
    (actions) => actions.submitCode(_digits),
    onWrongCode: (_) => _wrongCode = true,
  );

  void _onDigit(String digit) {
    if (_busy) return;
    setState(() {
      // After a wrong code, typing starts over.
      if (_wrongCode) _digits = '';
      _wrongCode = false;
      _error = null;
      _digits += digit;
    });
    if (_digits.length == _session!.codeLength) unawaited(_submit());
  }

  void _onDelete() {
    if (_busy || _digits.isEmpty) return;
    setState(() {
      _digits = _wrongCode ? '' : _digits.substring(0, _digits.length - 1);
      _wrongCode = false;
    });
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await ref.read(phoneValidationActionsProvider).cancel();
    } catch (_) {
      // Already over on the device, or the connection went: nothing to undo.
    }
    _busy = false;
    if (mounted) setState(_backToMethods);
  }

  /// Leaving the screen ends the session.
  void _cancelInBackground() {
    final actions = ref.read(phoneValidationActionsProvider);
    unawaited(() async {
      try {
        await actions.cancel();
      } catch (_) {
        // Same as in _cancel. It times out on the device otherwise.
      }
    }());
  }

  Future<void> _reviewApproval() async {
    await showCanReadWriteApprovalDialog(context);
    if (mounted) unawaited(_readMethods());
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    ref.listen(phoneAccessStateProvider, (_, next) => _onAccessChanged(next));
    final name = ref.watch(currentVehicleNameProvider) ?? 'the car';
    final running = _stage == _Stage.session;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _stage == _Stage.session) _cancelInBackground();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  subtitle: '$name · Bluetooth',
                  secondsLeft: running ? _secondsLeft : null,
                  onClose: _close,
                ),
                const SizedBox(height: 16),
                Expanded(child: _stageBody(name)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stageBody(String name) => switch (_stage) {
    _Stage.methods => _methodList(name),
    _Stage.session =>
      _session!.kind == _codeEntry ? _codeSession() : _inCarSession(),
    _Stage.validated => _Ending(
      icon: Symbols.check,
      title: 'This phone is validated',
      body:
          'You can control $name from this phone now. Other phones validate '
          'on their own.',
      actions: [WizardPrimaryButton(label: 'Done', onPressed: _close)],
    ),
    _Stage.tooManyWrongCodes => _Ending(
      icon: Symbols.lock,
      danger: true,
      title: 'Too many wrong codes',
      body:
          'For safety, no phone can try again for a while. '
          '${_cooldownLeft > 0 ? 'You can try again in ${_clock(_cooldownLeft)}.' : 'You can try again now.'}',
      actions: [WizardPrimaryButton(label: 'Close', onPressed: _close)],
    ),
    _Stage.timedOut => _Ending(
      icon: Symbols.timer_off,
      title: "Time's up",
      body: 'The validation ran out of time. You can start it again.',
      actions: [
        WizardPrimaryButton(
          label: 'Start again',
          onPressed: _busy ? null : _startAgain,
        ),
        TextButton(onPressed: _close, child: const Text('Close')),
      ],
    ),
    _Stage.otherPhone => _Ending(
      icon: Symbols.phonelink,
      title: 'Another phone is validating',
      body:
          'Only one phone can validate at a time. Try again when it has '
          'finished, or in '
          '${HelpScreen.duration(kBlePhoneValidationSessionSeconds)} at most.',
      actions: [
        WizardPrimaryButton(
          label: 'Try again',
          onPressed: _busy ? null : _startAgain,
        ),
        TextButton(onPressed: _close, child: const Text('Close')),
      ],
    ),
  };

  Widget _methodList(String name) {
    final tokens = context.tokens;
    final bodyStyle = AppTextStyles.wizardBody.copyWith(
      color: tokens.textSecondary,
    );
    final methods = _methods;
    final canAccess = ref.watch(canAccessStateProvider);
    final phone = ref.watch(phoneAccessStateProvider);
    final canApprove =
        canAccess != null &&
        canAccessNeedsApproval(canAccess) &&
        !(phone != null && isOutrankedByValidatedPhone(phone));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              Semantics(
                header: true,
                child: Text(
                  "Prove you're in the car",
                  style: AppTextStyles.wizardTitle,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Before this phone can control $name, do this in the car. '
                "Someone near the car can't do it from outside.",
                style: bodyStyle,
              ),
              const SizedBox(height: 16),
              if (_error case final error?) ...[
                _ErrorText(error),
                const SizedBox(height: 12),
              ],
              if (methods == null)
                _methodsFailed
                    ? Text(
                        "Couldn't read the car's validation methods. Stay "
                        'connected over Bluetooth.',
                        style: bodyStyle,
                      )
                    : const Center(child: CircularProgressIndicator())
              else if (methods.isEmpty)
                Text("This car can't validate phones yet.", style: bodyStyle)
              else
                for (final method in methods) ...[
                  _MethodCard(
                    method: method,
                    onStart: _busy || !method.available
                        ? null
                        : () => _start(method.methodId),
                    onReview:
                        !method.available && method.needsApproval && canApprove
                        ? _reviewApproval
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
        TextButton(onPressed: _close, child: const Text('Not now')),
      ],
    );
  }

  Widget _codeSession() {
    final tokens = context.tokens;
    final session = _session!;
    final text = phoneValidationMethodText(session.methodId, session.kind);
    final attempts = session.attemptsLeft;
    final message = _wrongCode
        ? 'Wrong code. $attempts ${attempts == 1 ? 'attempt' : 'attempts'} left.'
        : _error;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Enter the code shown in the car',
                  style: AppTextStyles.wizardTitle,
                ),
              ),
              Text(
                '${text.codeHint} Starting again shows a new code.',
                style: AppTextStyles.wizardBody.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _CodeBoxes(
                length: session.codeLength,
                digits: _digits,
                wrong: _wrongCode,
              ),
              if (message != null) _ErrorText(message),
              const SizedBox(height: 16),
              _Keypad(
                onDigit: _busy ? null : _onDigit,
                onDelete: _busy ? null : _onDelete,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _busy ? null : _startAgain,
                      child: const Text('Show a new code'),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: _busy ? null : _cancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inCarSession() {
    final tokens = context.tokens;
    final session = _session!;
    final text = phoneValidationMethodText(session.methodId, session.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              const Center(
                child: WizardMedallion(
                  icon: Symbols.directions_car,
                  rings: true,
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  'Do this in the car',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.wizardTitle,
                ),
              ),
              const SizedBox(height: 16),
              WizardCard(
                child: Column(
                  spacing: 12,
                  children: [
                    for (final (index, step) in text.instructions.indexed)
                      _InstructionStep(number: index + 1, text: step),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Waiting for the car…',
                textAlign: TextAlign.center,
                style: AppTextStyles.wizardBody.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        WizardSecondaryButton(
          label: 'Cancel',
          onPressed: _busy ? null : _cancel,
        ),
      ],
    );
  }
}

/// [seconds] as a clock: "1:42".
String _clock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

class _Header extends StatelessWidget {
  const _Header({
    required this.subtitle,
    required this.secondsLeft,
    required this.onClose,
  });

  final String subtitle;
  final int? secondsLeft;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final seconds = secondsLeft;
    return Row(
      spacing: 8,
      children: [
        IconButton(
          onPressed: onClose,
          icon: const Icon(Symbols.close),
          tooltip: 'Close',
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Validate this phone',
                  style: AppTextStyles.vehicleName,
                ),
              ),
              Text(
                subtitle,
                style: AppTextStyles.caption.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (seconds != null)
          Semantics(
            label: 'Time left: ${_clock(seconds)}',
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: ShapeDecoration(
                color: tokens.surface,
                shape: tokens.radiusPill.shape(
                  side: BorderSide(color: tokens.outline),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  const Icon(Symbols.schedule, size: 16),
                  Text(_clock(seconds), style: AppTextStyles.caption),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final danger = context.tokens.danger;
    return Row(
      spacing: 8,
      children: [
        Icon(Symbols.error, size: 18, color: danger),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.wizardNote.copyWith(color: danger),
          ),
        ),
      ],
    );
  }
}

/// One way of validating. Greyed out while the device can't start it, with a
/// way to the approval when that is what it needs.
class _MethodCard extends StatelessWidget {
  const _MethodCard({
    required this.method,
    required this.onStart,
    required this.onReview,
  });

  final PhoneValidationMethod method;
  final VoidCallback? onStart;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = phoneValidationMethodText(method.methodId, method.kind);
    final color = method.available ? tokens.text : tokens.textSecondary;
    final detail = AppTextStyles.wizardNote.copyWith(
      color: tokens.textSecondary,
    );
    return WizardCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onStart,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: ShapeDecoration(
                  color: tokens.accentContainer,
                  shape: tokens.radiusRound.shape(),
                ),
                child: Icon(
                  method.kind == _codeEntry
                      ? Symbols.pin
                      : Symbols.radio_button_checked,
                  color: method.available
                      ? tokens.onAccentContainer
                      : tokens.textSecondary,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      text.title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: color),
                    ),
                    Text(text.description, style: detail),
                    if (onReview != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Needs vehicle control approval',
                              style: detail.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: onReview,
                            child: const Text('Review'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (method.available)
                Icon(Symbols.chevron_right, color: tokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.length,
    required this.digits,
    required this.wrong,
  });

  final int length;
  final String digits;
  final bool wrong;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      label: 'Code, ${digits.length} of $length digits',
      excludeSemantics: true,
      child: Row(
        spacing: 8,
        children: [
          for (var i = 0; i < length; i++)
            Expanded(
              child: Container(
                height: 58,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: tokens.surface,
                  shape: tokens.radiusMedium.shape(
                    side: BorderSide(
                      width: wrong || i == digits.length ? 2 : 1,
                      color: wrong
                          ? tokens.danger
                          : i == digits.length
                          ? tokens.accent
                          : tokens.outline,
                    ),
                  ),
                ),
                child: Text(
                  i < digits.length ? digits[i] : '',
                  style: AppTextStyles.statValue,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onDelete});

  final ValueChanged<String>? onDigit;
  final VoidCallback? onDelete;

  Widget _digit(String digit) => _Key(
    key: ValueKey('validation-key-$digit'),
    onPressed: onDigit == null ? null : () => onDigit!(digit),
    child: Text(digit, style: AppTextStyles.statValue),
  );

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> keys) => Row(
      spacing: 8,
      children: [for (final key in keys) Expanded(child: key)],
    );
    return Column(
      spacing: 8,
      children: [
        for (final digits in const ['123', '456', '789'])
          row([for (final digit in digits.split('')) _digit(digit)]),
        row([
          const SizedBox.shrink(),
          _digit('0'),
          _Key(
            key: const ValueKey('validation-key-delete'),
            onPressed: onDelete,
            child: const Icon(Symbols.backspace, semanticLabel: 'Delete'),
          ),
        ]),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({super.key, required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        backgroundColor: tokens.glassFill,
        foregroundColor: tokens.text,
        shape: tokens.radiusMedium.shape(),
      ),
      child: child,
    );
  }
}

class _InstructionStep extends StatelessWidget {
  const _InstructionStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: tokens.accentContainer,
          foregroundColor: tokens.onAccentContainer,
          child: Text('$number', style: AppTextStyles.caption),
        ),
        Expanded(child: Text(text, style: AppTextStyles.wizardBody)),
      ],
    );
  }
}

/// How a validation ended.
class _Ending extends StatelessWidget {
  const _Ending({
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  Center(
                    child: WizardMedallion(icon: icon, danger: danger),
                  ),
                  Semantics(
                    header: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.wizardTitle,
                    ),
                  ),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.wizardBody.copyWith(
                      color: context.tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ...actions,
      ],
    );
  }
}
