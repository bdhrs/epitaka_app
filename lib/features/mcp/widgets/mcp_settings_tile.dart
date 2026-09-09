/// Settings tile for the local MCP server: on/off switch, live URL/status,
/// and a (?) button with per-platform setup instructions.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_dimensions.dart';
import '../../../core/theme/app_typography.dart';
import '../epitaka_tool_registry.dart';
import '../mcp_server_provider.dart';

class McpSettingsTile extends ConsumerWidget {
  const McpSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final mcp = ref.watch(mcpServerProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.md,
        vertical: AppDimensions.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, color: colors.primary),
              const SizedBox(width: AppDimensions.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'MCP Server',
                            style: AppTypography.labelMedium.copyWith(
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        _StatusDot(mcp: mcp),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mcp.running
                          ? mcp.localUrl
                          : 'Let AI apps query your Tipitaka',
                      style: AppTypography.labelSmall.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.help_outline, size: 20),
                color: colors.onSurfaceVariant,
                tooltip: 'How to use',
                onPressed: () => showMcpHelpDialog(context, ref),
              ),
              Switch(
                value: mcp.enabled,
                onChanged: (val) => ref
                    .read(mcpServerProvider.notifier)
                    .setEnabled(ProviderScope.containerOf(context), val),
              ),
            ],
          ),
          if (mcp.error != null) ...[
            const SizedBox(height: 4),
            Text(
              'Could not start: ${mcp.error}',
              style: AppTypography.labelSmall.copyWith(
                color: colors.error,
                fontSize: 11,
              ),
            ),
          ],
          if (mcp.running && mcp.lanUrl != null) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _copy(context, mcp.lanUrl!),
              child: Text(
                'LAN: ${mcp.lanUrl}  (tap to copy)',
                style: AppTypography.labelSmall.copyWith(
                  color: colors.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
  }
}

class _StatusDot extends StatelessWidget {
  final McpServerState mcp;

  const _StatusDot({required this.mcp});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = mcp.running
        ? Colors.green
        : mcp.enabled
        ? Colors.orange
        : colors.outline;
    final label = mcp.running
        ? 'on · ${kEpitakaTools.length} tools'
        : mcp.enabled
        ? 'starting…'
        : 'off';
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: colors.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// (?) help dialog: what MCP is, desktop setup, Android/phone limits,
///
/// install notes. English-only (like other technical sheets); the app's
/// `_t()` falls back to the key when a translation is missing.
Future<void> showMcpHelpDialog(BuildContext context, WidgetRef ref) async {
  final mcp = ref.read(mcpServerProvider);
  final url = mcp.localUrl;
  final configJson =
      '''
{
  "mcpServers": {
    "epitaka": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "$url"]
    }
  }
}''';
  final colors = Theme.of(context).colorScheme;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('MCP Server — how to use'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _h('What is this?'),
              _p(
                'MCP (Model Context Protocol) lets external AI apps call '
                'ePitaka directly — the same ${kEpitakaTools.length} tools '
                'Vīmaṃsā uses (search_tipitaka, get_dictionary, '
                'get_paragraph_content, …). Turn the switch on, keep ePitaka '
                'open, and point your AI client at the URL below.',
              ),
              _urlBox(colors, url, ctx),
              _h('Desktop (Claude Desktop, Cherry Studio, LibreChat)'),
              _p(
                '1. Install Node.js, then add this to your client\'s MCP config '
                '(Claude Desktop: Settings → Developer → Edit Config):',
              ),
              _codeBox(colors, configJson, ctx),
              _p(
                '2. Restart the AI client. Its tool list should now include '
                'search_tipitaka, get_books, etc.\n'
                '3. Remote-direct alternative: some clients accept a '
                'Streamable-HTTP URL — enter $url directly.',
              ),
              _h('Android phone (ChatGPT / Gemini apps)'),
              _p(
                'The ChatGPT and Gemini mobile apps cannot reach a server '
                'running on the phone itself (no localhost MCP support), so '
                'there is no direct on-phone setup. Workarounds:\n'
                '• Same-WiFi: on a desktop AI client, use the LAN URL shown '
                'under the switch (phone + computer on the same Wi-Fi).\n'
                '• Tunnel: expose the port with Cloudflare Tunnel / ngrok, '
                'then add the public URL as a remote MCP server in the web '
                'version of your AI client.\n'
                '• Keep ePitaka in the foreground while querying — Android '
                'may suspend background servers on some devices.',
              ),
              _h('Speed tips (for custom clients / scripts)'),
              _p(
                '• Set your HTTP timeout to 90s — the first search after '
                'launch can take a while on cold databases.\n'
                '• Pass a small "limit" (e.g. 10) to search tools and '
                '"limit/offset" to get_books — fewer rows answer in seconds.\n'
                '• At most 2 tool calls run at once; extras get an instant '
                'HTTP 503 with Retry-After instead of hanging.',
              ),
              _h('Install notes'),
              _p(
                '• Desktop: no firewall change needed for 127.0.0.1. For LAN '
                'access, allow inbound TCP on the port.\n'
                '• Android: uses your Wi-Fi connection (INTERNET permission, '
                'already declared). No extra install — the server is built in.\n'
                '• iOS: same as Android; keep the app open while in use.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Widget _h(String text) => Padding(
  padding: const EdgeInsets.only(top: 12, bottom: 4),
  child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
);

Widget _p(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4)),
);

Widget _urlBox(ColorScheme colors, String url, BuildContext ctx) => Container(
  width: double.infinity,
  margin: const EdgeInsets.only(bottom: 8),
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
    color: colors.surfaceContainerLow,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Row(
    children: [
      Expanded(
        child: SelectableText(url, style: const TextStyle(fontSize: 13)),
      ),
      IconButton(
        icon: const Icon(Icons.copy, size: 18),
        tooltip: 'Copy URL',
        onPressed: () {
          Clipboard.setData(ClipboardData(text: url));
          ScaffoldMessenger.of(
            ctx,
          ).showSnackBar(const SnackBar(content: Text('URL copied')));
        },
      ),
    ],
  ),
);

Widget _codeBox(ColorScheme colors, String code, BuildContext ctx) => Container(
  width: double.infinity,
  margin: const EdgeInsets.only(bottom: 8),
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
    color: colors.surfaceContainerLow,
    borderRadius: BorderRadius.circular(8),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: SelectableText(
          code,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.copy, size: 18),
        tooltip: 'Copy config',
        onPressed: () {
          Clipboard.setData(ClipboardData(text: code));
          ScaffoldMessenger.of(
            ctx,
          ).showSnackBar(const SnackBar(content: Text('Config copied')));
        },
      ),
    ],
  ),
);
