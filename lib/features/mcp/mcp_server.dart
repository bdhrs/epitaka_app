/// Local MCP (Model Context Protocol) server exposing the shared ePitaka
/// tools over Streamable HTTP (`POST /mcp`) using pure `dart:io`.
///
/// No new dependencies: JSON-RPC 2.0 is handled manually. Any MCP client
/// that supports Streamable HTTP / SSE (Claude Desktop via `mcp-remote`,
/// Cherry Studio, LibreChat, Home Assistant, …) can call the same tools
/// Vīmaṃsā uses — see `epitaka_tool_registry.dart`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_db_provider.dart';
import '../../core/providers/database_provider.dart';
import '../ai_qa/services/ai_qa_tool_service.dart';
import '../ai_qa/services/section_index_service.dart';
import 'epitaka_tool_registry.dart';

const String kMcpProtocolVersion = '2025-06-18';
const String kMcpServerName = 'epitaka';
const String kMcpServerVersion = '1.1.0';

/// Max parallel tool executions. Drift serializes heavy queries anyway, so
/// beyond this the server just gets slower for everyone — extra callers get
/// an immediate 503 + `isError` instead of a hung socket that the client
/// eventually reads as an empty body.
const int kMcpMaxInflightTools = 2;

/// Reject JSON-RPC bodies larger than this (fast 413, never hang).
const int kMcpMaxBodyBytes = 256 * 1024;

/// Cap tool result text sent over the transport (fast fail against
/// client-side truncation/empty reads on huge payloads).
const int kMcpMaxToolChars = 120000;

typedef McpToolExecutor =
    Future<ToolResult> Function(String name, Map<String, dynamic> args);

/// A minimal MCP server bound to loopback + LAN.
///
/// Endpoints:
/// - `GET /health` → `{"status":"ok","tools":N}` (no auth, for the UI dot)
/// - `POST /mcp` → JSON-RPC (Streamable HTTP, stateless)
/// - `GET /mcp` → SSE event stream (kept open; clients that probe it)
/// - `GET /` → server info JSON
class McpServer {
  HttpServer? _server;
  McpToolExecutor? _executor;

  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;

  Future<int> start({
    required int port,
    required McpToolExecutor executor,
  }) async {
    await stop();
    _executor = executor;
    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: false,
    );
    debugPrint('[MCP] listening on port ${_server!.port}');
    _server!.listen(_handleRequest);
    return _server!.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _executor = null;
    if (server != null) {
      await server.close(force: true);
      debugPrint('[MCP] stopped');
    }
  }

  /// Build an executor from a Riverpod container. Reads the shared
  /// [AiQaToolService] so MCP calls hit the exact same code as Vīmaṃsā.
  static McpToolExecutor executorFor(ProviderContainer container) {
    return (name, args) async {
      final service = container.read(aiQaToolServiceProvider);
      return dispatchTool(service, name, args);
    };
  }

  int _inflight = 0;
  final Set<String> _sessions = {};

  /// Pre-open the databases + kick the section-index build so the FIRST
  /// tool call doesn't pay cold-open/lazy-build seconds. Called once after
  /// [start]; never blocks serving (index build runs detached).
  Future<void> warmUp(ProviderContainer container) async {
    try {
      await container.read(epitakaDbProvider.future);
      await container.read(appDbProvider.future);
      await container.read(translationDbProvider('en').future);
      debugPrint('[MCP] databases warm');
    } catch (e) {
      debugPrint('[MCP] warmup DBs skipped: $e');
    }
    try {
      unawaited(
        container
            .read(sectionIndexServiceProvider)
            .ensureIndex()
            .then((_) {
              debugPrint('[MCP] section index warm');
            })
            .catchError((Object e) {
              debugPrint('[MCP] section warmup skipped: $e');
            }),
      );
    } catch (e) {
      debugPrint('[MCP] warmup index skipped: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      _applyCors(request.response);
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }
      final path = request.uri.path;
      if (path == '/health' && request.method == 'GET') {
        return _json(request, {
          'status': 'ok',
          'server': kMcpServerName,
          'tools': kEpitakaTools.length,
        });
      }
      if ((path == '/' || path == '/info') && request.method == 'GET') {
        return _json(request, {
          'name': kMcpServerName,
          'version': kMcpServerVersion,
          'protocol': kMcpProtocolVersion,
          'transport': 'streamable-http',
          'endpoint': '/mcp',
          'tools': [for (final t in kEpitakaTools) t.name],
        });
      }
      if (path == '/mcp' && request.method == 'GET') {
        return _handleSseProbe(request);
      }
      if (path == '/mcp' && request.method == 'POST') {
        return _handleRpc(request);
      }
      if (path == '/mcp' && request.method == 'DELETE') {
        final sessionId = request.headers.value('mcp-session-id');
        if (sessionId != null) _sessions.remove(sessionId);
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await _json(request, {'error': 'not found. POST JSON-RPC to /mcp'});
    } catch (e) {
      debugPrint('[MCP] request error: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await _json(request, {'error': '$e'});
      } catch (_) {}
    }
  }

  /// Some clients probe `GET /mcp` expecting an SSE stream. Hold it briefly
  /// with the correct content type so the probe succeeds; stateless POST
  /// remains the real transport.
  Future<void> _handleSseProbe(HttpRequest request) async {
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.set('Content-Type', 'text/event-stream');
    response.headers.set('Cache-Control', 'no-cache');
    response.headers.set('Connection', 'keep-alive');
    response.write(': epitaka mcp\n\n');
    await response.flush();
    await Future<void>.delayed(const Duration(seconds: 25));
    try {
      await response.close();
    } catch (_) {}
  }

  Future<void> _handleRpc(HttpRequest request) async {
    final expectedToken = _bearerToken;
    if (expectedToken != null && expectedToken.isNotEmpty) {
      final auth = request.headers.value('authorization') ?? '';
      if (auth != 'Bearer $expectedToken') {
        request.response.statusCode = HttpStatus.unauthorized;
        return _json(request, {'error': 'unauthorized'});
      }
    }
    final body = await utf8.decoder.bind(request).join();
    if (body.length > kMcpMaxBodyBytes) {
      return _json(
        request,
        _rpcError(null, -32700, 'Request body too large'),
        status: HttpStatus.requestEntityTooLarge,
      );
    }
    // Track (but never require) client sessions for spec compatibility.
    final clientSession = request.headers.value('mcp-session-id');
    if (clientSession != null && clientSession.isNotEmpty) {
      _sessions.add(clientSession);
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(body.isEmpty ? '{}' : body);
    } catch (_) {
      return _jsonRpcError(request, null, -32700, 'Parse error');
    }
    if (decoded is List) {
      // Batch: always HTTP 200; per-item errors ride inside the array.
      final responses = <Map<String, dynamic>>[];
      for (final item in decoded) {
        final r = await _dispatch(
          item is Map<String, dynamic> ? item : <String, dynamic>{},
        );
        if (r.body != null) responses.add(r.body!);
      }
      return _json(request, responses);
    }
    final response = await _dispatch(
      decoded is Map<String, dynamic> ? decoded : <String, dynamic>{},
    );
    if (response.body == null) {
      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
      return;
    }
    return _json(
      request,
      response.body!,
      status: response.status,
      headers: response.headers,
    );
  }

  String? _bearerToken;

  // ignore: use_setters_to_change_properties
  void setBearerToken(String? token) => _bearerToken = token;

  String _newSessionId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// Dispatch result carrying its own HTTP status + headers (per-request,
  /// so concurrent calls can fail fast with 503 independently).
  ({int status, Map<String, dynamic>? body, Map<String, String> headers}) _resp(
    Map<String, dynamic>? body, {
    int status = HttpStatus.ok,
    Map<String, String> headers = const {},
  }) => (status: status, body: body, headers: headers);

  Future<
    ({int status, Map<String, dynamic>? body, Map<String, String> headers})
  >
  _dispatch(Map<String, dynamic> msg) async {
    final id = msg['id'];
    final method = (msg['method'] as String?) ?? '';
    // Notifications (no id) need no reply.
    if (method.startsWith('notifications/')) return _resp(null);
    if (msg['jsonrpc'] != '2.0' || method.isEmpty) {
      return _resp(_rpcError(id, -32600, 'Invalid Request'));
    }
    final params = msg['params'] is Map
        ? Map<String, dynamic>.from(msg['params'] as Map)
        : <String, dynamic>{};
    try {
      switch (method) {
        case 'initialize':
          final sessionId = _newSessionId();
          _sessions.add(sessionId);
          return _resp(
            _rpcOk(id, {
              'protocolVersion': kMcpProtocolVersion,
              'capabilities': {
                'tools': {'listChanged': false},
              },
              'serverInfo': {
                'name': kMcpServerName,
                'version': kMcpServerVersion,
              },
            }),
            headers: {'Mcp-Session-Id': sessionId},
          );
        case 'ping':
          return _resp(_rpcOk(id, {}));
        case 'tools/list':
          return _resp(
            _rpcOk(id, {
              'tools': [for (final t in kEpitakaTools) t.toMcpTool()],
            }),
          );
        case 'tools/call':
          return _callTool(id, params);
        case 'resources/list':
          return _resp(_rpcOk(id, {'resources': []}));
        case 'prompts/list':
          return _resp(_rpcOk(id, {'prompts': []}));
        default:
          return _resp(_rpcError(id, -32601, 'Method not found: $method'));
      }
    } catch (e) {
      return _resp(_rpcError(id, -32603, 'Internal error: $e'));
    }
  }

  Future<
    ({int status, Map<String, dynamic>? body, Map<String, String> headers})
  >
  _callTool(dynamic id, Map<String, dynamic> params) async {
    final name = (params['name'] as String?) ?? '';
    final args = params['arguments'] is Map
        ? Map<String, dynamic>.from(params['arguments'] as Map)
        : <String, dynamic>{};
    final executor = _executor;
    if (executor == null) {
      return _resp(_rpcError(id, -32603, 'Server not ready'));
    }
    if (_inflight >= kMcpMaxInflightTools) {
      // Fast-fail under load: a proper 503 + JSON-RPC error + isError
      // instead of a hung socket the client reads as an empty body.
      debugPrint('[MCP] tools/call $name rejected: busy ($_inflight inflight)');
      return _resp(
        _rpcError(
          id,
          -32000,
          'Server busy ($_inflight tool call(s) running). '
          'Retry in 2s with a smaller limit.',
        ),
        status: HttpStatus.serviceUnavailable,
        headers: {'Retry-After': '2'},
      );
    }
    debugPrint('[MCP] tools/call $name (inflight=${_inflight + 1})');
    _inflight++;
    final stopwatch = Stopwatch()..start();
    try {
      ToolResult result;
      try {
        result = await executor(name, args).timeout(const Duration(minutes: 2));
      } on TimeoutException {
        return _resp(
          _rpcOk(id, {
            'content': [
              {'type': 'text', 'text': 'Tool timed out after 2 minutes: $name'},
            ],
            'isError': true,
          }),
        );
      } catch (e) {
        return _resp(
          _rpcOk(id, {
            'content': [
              {'type': 'text', 'text': 'Tool error: $e'},
            ],
            'isError': true,
          }),
        );
      }
      var text = result.success
          ? result.data
          : 'Error: ${result.errorMessage ?? "tool failed"}\n${result.data}';
      if (text.length > kMcpMaxToolChars) {
        text =
            '${text.substring(0, kMcpMaxToolChars)}…'
            '[truncated ${text.length - kMcpMaxToolChars} chars by MCP server; '
            're-call with a smaller limit/offset]';
      }
      debugPrint(
        '[MCP] tools/call $name done in ${stopwatch.elapsedMilliseconds}ms '
        '(${text.length} chars)',
      );
      return _resp(
        _rpcOk(id, {
          'content': [
            {'type': 'text', 'text': text},
          ],
          'isError': !result.success,
        }),
      );
    } finally {
      _inflight--;
    }
  }

  Map<String, dynamic> _rpcOk(dynamic id, Map<String, dynamic> result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  Map<String, dynamic> _rpcError(dynamic id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  Future<void> _jsonRpcError(
    HttpRequest request,
    dynamic id,
    int code,
    String message,
  ) => _json(request, _rpcError(id, code, message));

  Future<void> _json(
    HttpRequest request,
    Object body, {
    int status = HttpStatus.ok,
    Map<String, String> headers = const {},
  }) async {
    final response = request.response;
    response.statusCode = status;
    for (final entry in headers.entries) {
      response.headers.set(entry.key, entry.value);
    }
    if (response.headers.value('content-type') == null) {
      response.headers.set('Content-Type', 'application/json');
    }
    response.write(jsonEncode(body));
    await response.close();
  }

  void _applyCors(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Methods',
      'GET, POST, DELETE, OPTIONS',
    );
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, Authorization, Mcp-Session-Id, Last-Event-ID',
    );
  }
}

/// Global singleton — one HTTP listener per process.
final mcpServer = McpServer();
