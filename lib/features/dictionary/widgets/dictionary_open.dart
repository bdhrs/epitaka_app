import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/responsive_breakpoint.dart';
import '../../../shared/providers/side_panel_provider.dart';
import 'dictionary_sheet.dart';

/// Route a dictionary lookup to the dictionary panel (desktop) or the modal
/// bottom sheet (mobile).
///
/// Desktop: the dictionary lives in the shell — docked in the sidebar (its
/// height is user-resizable and its placement is remembered), or as an
/// independent right column when the sidebar is closed. When it is already
/// open, the lookup simply re-points it at the new word in place (the panel
/// syncs with [sidePanelProvider]).
///
/// Mobile: the dictionary is the modal bottom sheet — easy to close with the
/// back button, by pulling it down, or by tapping outside.
///
/// Returns `true` when the lookup was handled (always, including empty
/// words); returns `false` when the caller should fall back to showing the
/// dictionary bottom sheet itself (never happens today — kept for symmetry).
///
/// When [closeSheet] is true (used from modal preview sheets), the current
/// route is popped first so the opened dictionary isn't hidden behind the
/// sheet.
///
/// When [forceSheet] is true, the lookup is always presented as a modal
/// bottom sheet stacked ON TOP of the current route (the desktop dock panel
/// is skipped). Used for lookups launched from inside a preview/book-link
/// sheet: the dictionary overlays the sheet, and closing it returns to the
/// content underneath (e.g. the commentary the user was reading).
bool openDictionaryInPanel(
  BuildContext context,
  WidgetRef ref,
  String word, {
  bool closeSheet = false,
  bool forceSheet = false,
}) {
  final trimmed = word.trim();
  if (trimmed.isEmpty) return true;

  if (closeSheet && Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }

  if (!forceSheet && ResponsiveBreakpoint.isDesktop(context)) {
    // Desktop: docked sidebar panel / right column. Decided by the ACTUAL
    // layout (not just the OS): a desktop window narrowed below the
    // desktop breakpoint falls back to the phone UI, and the docked panel
    // isn't rendered there — so the modal bottom sheet is used instead.
    final notifier = ref.read(sidePanelProvider.notifier);
    final sidePanels = ref.read(sidePanelProvider);
    if (sidePanels.isDictionaryOpen) {
      // Already visible — just point it at the new word. Keep this tolerant
      // of either sidebar slot so a resize or side switch cannot strand the
      // lookup in the wrong panel.
      notifier.updateDictionaryWord(trimmed);
    } else {
      // Open it; the shell (sidebar dock / right column) decides the exact
      // placement.
      notifier.open(SidePanelType.dictionary, data: trimmed, pin: true);
    }
  } else {
    // Mobile (or forced from inside a modal sheet): modal bottom sheet —
    // back button, pull down, or tap outside to close.
    showDictionarySheet(context, trimmed);
  }
  return true;
}
