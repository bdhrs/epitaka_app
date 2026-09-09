/// Restarts the MCP server on app launch when the user left it enabled.
///
/// Mounted once above [MaterialApp] in [EpitakaApp]; the toggle in Settings
/// handles start/stop afterwards, so this only covers the cold-start path
/// (the persisted flag loads async, hence the listen + post-frame ensure).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mcp_server_provider.dart';

class McpAutoStart extends ConsumerStatefulWidget {
  final Widget child;

  const McpAutoStart({super.key, required this.child});

  @override
  ConsumerState<McpAutoStart> createState() => _McpAutoStartState();
}

class _McpAutoStartState extends ConsumerState<McpAutoStart> {
  bool _ensured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
  }

  Future<void> _ensure() async {
    if (_ensured || !mounted) return;
    _ensured = true;
    try {
      final container = ProviderScope.containerOf(context);
      await container.read(mcpServerProvider.notifier).ensureStarted(container);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(mcpServerProvider.select((s) => s.enabled), (_, enabled) {
      if (enabled) _ensured = false;
      _ensure();
    });
    return widget.child;
  }
}
