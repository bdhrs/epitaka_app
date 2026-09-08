import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Manual override for the setup-wizard "Keep screen on" switch.
///
/// `null` means automatic: the screen stays awake while a download or the
/// index build is running (or the global reading setting is on).
final keepAwakeOverrideProvider = StateProvider<bool?>((ref) => null);

/// Single place that toggles the platform screen wakelock.
///
/// Sources are OR-ed: the screen stays awake when ANY of them wants it —
/// the global "Keep Screen On" reading setting, the wizard's manual switch,
/// or an actively running download / index build.
///
/// Platform notes (no extra permissions required anywhere):
/// * Android — `FLAG_KEEP_SCREEN_ON` (`WAKE_LOCK` is already declared).
/// * iOS — `idleTimerDisabled`. No permission needed.
/// * macOS / Windows / Linux — native idle inhibition. No permission needed.
/// * Web — Screen Wake Lock API; silently ignored when unsupported.
class KeepAwake {
  static bool _enabled = false;

  static Future<void> apply({
    required bool global,
    required bool busy,
    required bool? override,
  }) async {
    final want = override ?? (global || busy);
    if (want == _enabled) return;
    _enabled = want;
    try {
      await WakelockPlus.toggle(enable: want);
    } catch (e) {
      developer.log(
        '[KEEP_AWAKE] toggle($want) failed: $e',
        name: 'epitaka.keepawake',
      );
    }
  }
}
