import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The ids of the command controls waiting for the vehicle's answer.
///
/// Kept here rather than in each control so it survives the control being
/// rebuilt, and so the connection pill can show that something is being sent.
class PendingCommandControlsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Marks [id] as pending. False if it already is, so a second tap doesn't
  /// send the command twice.
  bool begin(String id) {
    if (state.contains(id)) return false;
    state = {...state, id};
    return true;
  }

  void end(String id) => state = {...state}..remove(id);
}

final pendingCommandControlsProvider =
    NotifierProvider<PendingCommandControlsNotifier, Set<String>>(
      PendingCommandControlsNotifier.new,
    );
