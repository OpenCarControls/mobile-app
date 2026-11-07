import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:open_car_app/providers/command_availability_provider.dart';
import 'package:open_car_app/providers/pending_command_controls_provider.dart';
import 'package:open_car_app/theme/app_tokens.dart';
import 'package:open_car_app/widgets/vehicle_command_feedback.dart';

/// Touch targets are never smaller than this, in dp.
const double kMinTouchTarget = 44;

const _unavailableOpacity = 0.45;
const _pendingBorderWidth = 2.0;
const _failureTintOpacity = 0.35;
const _shakeDistance = 5.0;
const _shakeCount = 3;
const _failureDuration = Duration(milliseconds: 700);

/// Without motion the failure holds still, so it stays up long enough to see.
const _failureDurationReduced = Duration(milliseconds: 1500);

/// Makes [child] send a vehicle command: a whole command tile, or one button
/// inside a bigger tile.
///
/// While the device doesn't accept [command] it is greyed out and a tap says
/// why. While [send] runs it pulses and ignores taps. If [send] fails, it
/// flashes red and shakes, and [sendVehicleCommand] says why in a SnackBar.
///
/// Commands the car doesn't have show nothing. Leave a whole tile out of the
/// grid for those, or its place stays empty.
class CommandControl extends ConsumerStatefulWidget {
  const CommandControl({
    super.key,
    required this.id,
    required this.command,
    required this.send,
    required this.semanticLabel,
    required this.shape,
    required this.child,
  });

  /// What pulses while pending. Controls can share a [command], as the climate
  /// extras do, and only the one pressed should pulse.
  final String id;

  /// The command whose availability applies.
  final CommandKey command;

  /// Sends the command. Completes when the vehicle answers and throws if it
  /// doesn't accept it.
  final Future<Object?> Function() send;

  /// The label for screen readers, including the state ("Doors, locked").
  final String semanticLabel;

  /// The outline of [child], for the ripple and the state's border.
  final OutlinedBorder shape;

  final Widget child;

  @override
  ConsumerState<CommandControl> createState() => _CommandControlState();
}

class _CommandControlState extends ConsumerState<CommandControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _failure;

  @override
  void initState() {
    super.initState();
    _failure = AnimationController(vsync: this, duration: _failureDuration);
  }

  @override
  void dispose() {
    _failure.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (ref.read(commandUiStateProvider(widget.command)) !=
        CommandUiState.enabled) {
      showVehicleCommandMessage(
        context,
        ref,
        ref.read(commandUnavailableReasonProvider(widget.command)),
      );
      return;
    }
    final id = widget.id;
    final pending = ref.read(pendingCommandControlsProvider.notifier);
    if (!pending.begin(id)) return;
    final bool sent;
    try {
      sent = await sendVehicleCommand(context, ref, widget.send);
    } finally {
      pending.end(id);
    }
    if (sent || !mounted) return;
    _failure.duration = MediaQuery.disableAnimationsOf(context)
        ? _failureDurationReduced
        : _failureDuration;
    _failure.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final availability = ref.watch(commandUiStateProvider(widget.command));
    if (availability == CommandUiState.hidden) return const SizedBox.shrink();
    final unavailable = availability != CommandUiState.enabled;
    final pending = ref.watch(
      pendingCommandControlsProvider.select((ids) => ids.contains(widget.id)),
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tokens = context.tokens;

    final state = pending
        ? 'sending'
        : unavailable
        ? 'not available'
        : null;
    return Semantics(
      container: true,
      button: true,
      label: [widget.semanticLabel, ?state].join(', '),
      onTap: _onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: kMinTouchTarget,
          minHeight: kMinTouchTarget,
        ),
        child: AnimatedBuilder(
          animation: _failure,
          builder: (context, child) {
            final t = _failure.value;
            final failing = _failure.isAnimating;
            // Fades out with the shake; without motion it holds, then ends.
            final flash = !failing
                ? 0.0
                : reduceMotion
                ? 1.0
                : 1 - t;
            final dx = reduceMotion || !failing
                ? 0.0
                : math.sin(t * _shakeCount * 2 * math.pi) *
                      _shakeDistance *
                      (1 - t);
            return Transform.translate(
              offset: Offset(dx, 0),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  child!,
                  if (flash > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: tokens.danger.withValues(
                              alpha: _failureTintOpacity * flash,
                            ),
                            shape: widget.shape.copyWith(
                              side: BorderSide(
                                color: tokens.danger.withValues(alpha: flash),
                                width: _pendingBorderWidth,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
          child: _Pulse(
            active: pending && !reduceMotion,
            child: Opacity(
              opacity: unavailable ? _unavailableOpacity : 1,
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  widget.child,
                  if (pending)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            shape: widget.shape.copyWith(
                              side: BorderSide(
                                color: tokens.accent,
                                width: _pendingBorderWidth,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(customBorder: widget.shape, onTap: _onTap),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades [child] in and out while [active].
class _Pulse extends StatefulWidget {
  const _Pulse({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final _opacity = Tween<double>(
    begin: 1,
    end: 0.55,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Pulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}
