import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'library_browser.dart';

/// A compact library panel for the left sidebar on desktop.
///
/// Shows the Tipitaka book tree directly. Reading history and bookmarks
/// live in their own sidebar panels, so no Browse / Reading / Bookmarks
/// tabs are shown here (those remain on the mobile [LibraryScreen]).
class LibraryPanel extends ConsumerWidget {
  /// When true, the type-to-filter field is focused once the panel is
  /// built (used by the Cmd/Ctrl+L shortcut).
  final bool autoFocus;

  const LibraryPanel({super.key, this.autoFocus = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LibraryBrowser(
      maxWidth: double.infinity,
      autoFocusFilter: autoFocus,
    );
  }
}
