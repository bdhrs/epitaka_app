/// Riverpod state for the local MCP server: on/off switch, port, optional
/// bearer token, live URL/status. Persisted in SharedPreferences.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'epitaka_tool_registry.dart';
import 'mcp_server.dart';

const int kMcpDefaultPort = 3847;
const String _kMcpEnabledKey = 'mcp_enabled';
const String _kMcpPortKey = 'mcp_port';
const String _kMcpTokenKey = 'mcp_token';

class McpServerState {
  final bool enabled;
  final bool running;
  final int port;
  final int actualPort;
  final String token;
  final String? error;
  final String? lanIp;

  const McpServerState({
    this.enabled = false,
    this.running = false,
    this.port = kMcpDefaultPort,
    this.actualPort = 0,
    this.token = '',
    this.error,
    this.lanIp,
  });

  int get effectivePort => actualPort != 0 ? actualPort : port;
  String get localUrl => 'http://127.0.0.1:$effectivePort/mcp';
  String? get lanUrl =>
      lanIp == null ? null : 'http://$lanIp:$effectivePort/mcp';

  McpServerState copyWith({
    bool? enabled,
    bool? running,
    int? port,
    int? actualPort,
    String? token,
    String? error,
    String? lanIp,
  }) => McpServerState(
    enabled: enabled ?? this.enabled,
    running: running ?? this.running,
    port: port ?? this.port,
    actualPort: actualPort ?? this.actualPort,
    token: token ?? this.token,
    error: error,
    lanIp: lanIp ?? this.lanIp,
  );
}

class McpServerNotifier extends StateNotifier<McpServerState> {
  McpServerNotifier() : super(const McpServerState()) {
    _load();
  }

  bool _starting = false;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_kMcpEnabledKey) ?? false;
      final port = prefs.getInt(_kMcpPortKey) ?? kMcpDefaultPort;
      final token = prefs.getString(_kMcpTokenKey) ?? '';
      state = state.copyWith(enabled: enabled, port: port, token: token);
    } catch (e) {
      debugPrint('[MCP] prefs load skipped: $e');
    }
  }

  Future<void> setEnabled(ProviderContainer container, bool enabled) async {
    state = state.copyWith(enabled: enabled, error: null);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kMcpEnabledKey, enabled);
    } catch (_) {}
    if (enabled) {
      await start(container);
    } else {
      await stop();
    }
  }

  Future<void> setPort(ProviderContainer container, int port) async {
    final clamped = port.clamp(1024, 65535);
    state = state.copyWith(port: clamped, error: null);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kMcpPortKey, clamped);
    } catch (_) {}
    if (state.enabled) await start(container);
  }

  Future<void> regenerateToken(ProviderContainer container) async {
    final token = _randomToken();
    state = state.copyWith(token: token);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kMcpTokenKey, token);
    } catch (_) {}
    if (state.enabled) await start(container);
  }

  Future<void> clearToken(ProviderContainer container) async {
    state = state.copyWith(token: '');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kMcpTokenKey);
    } catch (_) {}
    if (state.enabled) await start(container);
  }

  Future<void> start(ProviderContainer container) async {
    if (_starting || mcpServer.isRunning) {
      if (mcpServer.isRunning) {
        state = state.copyWith(
          running: true,
          actualPort: mcpServer.port,
          lanIp: await _lanIp(),
          error: null,
        );
      }
      return;
    }
    _starting = true;
    try {
      mcpServer.setBearerToken(state.token.isEmpty ? null : state.token);
      int actual = state.port;
      try {
        actual = await mcpServer.start(
          port: state.port,
          executor: McpServer.executorFor(container),
        );
      } on SocketException catch (_) {
        // Port busy — fall back to any free port so the toggle still works.
        actual = await mcpServer.start(
          port: 0,
          executor: McpServer.executorFor(container),
        );
      }
      state = state.copyWith(
        running: true,
        actualPort: actual,
        lanIp: await _lanIp(),
        error: null,
      );
      debugPrint(
        '[MCP] started ${state.localUrl} (${kEpitakaTools.length} tools)',
      );
      // Cold-start mitigation: pre-open DBs + kick the section index build
      // in the background so the first tools/call answers in seconds.
      unawaited(mcpServer.warmUp(container));
    } catch (e) {
      state = state.copyWith(running: false, error: '$e');
      debugPrint('[MCP] start failed: $e');
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    await mcpServer.stop();
    state = state.copyWith(running: false, actualPort: 0, error: null);
  }

  /// Called once at startup: if the user left the switch on, listen again.
  Future<void> ensureStarted(ProviderContainer container) async {
    if (state.enabled && !mcpServer.isRunning) await start(container);
  }
}

final mcpServerProvider =
    StateNotifierProvider<McpServerNotifier, McpServerState>(
      (ref) => McpServerNotifier(),
    );

String _randomToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  return [for (final b in bytes) chars[b % chars.length]].join();
}

Future<String?> _lanIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        final ip = addr.address;
        if (ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            (ip.startsWith('172.') && _isPrivate172(ip))) {
          return ip;
        }
      }
    }
    if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
      return interfaces.first.addresses.first.address;
    }
  } catch (e) {
    debugPrint('[MCP] LAN IP lookup skipped: $e');
  }
  return null;
}

bool _isPrivate172(String ip) {
  final parts = ip.split('.');
  final second = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return second >= 16 && second <= 31;
}
