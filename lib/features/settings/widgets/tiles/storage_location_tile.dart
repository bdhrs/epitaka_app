import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/app_localizations.dart';
import '../../../../core/utils/database_initializer.dart';

class _DbFile {
  final String name;
  final int bytes;
  const _DbFile(this.name, this.bytes);
}

class _StorageInfo {
  final String path;
  final List<_DbFile> files;
  const _StorageInfo(this.path, this.files);
  int get totalBytes => files.fold(0, (s, f) => s + f.bytes);
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

Future<_StorageInfo> _loadStorageInfo() async {
  final dir = await getDatabaseDirectory();
  final files = <_DbFile>[];
  try {
    for (final e in dir.listSync()) {
      if (e is! File) continue;
      final name = e.path.split(Platform.pathSeparator).last;
      if (!name.endsWith('.db')) continue;
      int size = 0;
      try {
        size = e.lengthSync();
      } catch (_) {}
      files.add(_DbFile(name, size));
    }
  } catch (_) {}
  files.sort((a, b) => a.name.compareTo(b.name));
  return _StorageInfo(dir.path, files);
}

Future<void> _copyPath(BuildContext context, String path) async {
  final loc = AppLocalizations.of(context);
  await Clipboard.setData(ClipboardData(text: path));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(loc.pathCopied),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<void> _openFolder(BuildContext context, String path) async {
  final loc = AppLocalizations.of(context);
  try {
    final ok = await launchUrl(
      Uri.file(path),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${loc.couldNotOpenFolder}$path'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${loc.couldNotOpenFolder}$e'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

void _showDetails(BuildContext context, _StorageInfo info) {
  final colors = Theme.of(context).colorScheme;
  final loc = AppLocalizations.of(context);
  final showOpen = !Platform.isAndroid && !Platform.isIOS;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.storageLocation),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  info.path,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${info.files.length} databases • ${_formatBytes(info.totalBytes)}',
                style: AppTypography.labelSmall.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final f in info.files)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          f.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _formatBytes(f.bytes),
                        style: AppTypography.labelSmall.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              if (info.files.isEmpty)
                Text(
                  loc.noDatabasesFound,
                  style: AppTypography.labelSmall.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            _copyPath(context, info.path);
          },
          child: Text(loc.copyPath),
        ),
        if (showOpen)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openFolder(context, info.path);
            },
            icon: const Icon(Icons.folder_open, size: 18),
            label: Text(loc.openFolder),
          ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(loc.close),
        ),
      ],
    ),
  );
}

class StorageLocationTile extends StatelessWidget {
  const StorageLocationTile({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);
    final showOpen = !Platform.isAndroid && !Platform.isIOS;

    return FutureBuilder<_StorageInfo>(
      future: _loadStorageInfo(),
      builder: (context, snap) {
        final info = snap.data;
        final subtitle = info == null
            ? loc.loadingDatabases
            : '${info.files.length} databases • ${_formatBytes(info.totalBytes)}\n${info.path}';
        return InkWell(
          onTap: info == null ? null : () => _showDetails(context, info),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.md,
              vertical: AppDimensions.md,
            ),
            child: Row(
              children: [
                Icon(Icons.folder_open, color: colors.primary),
                const SizedBox(width: AppDimensions.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.storageLocation,
                        style: AppTypography.labelMedium.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.labelSmall.copyWith(
                          color: colors.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (info != null) ...[
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    color: colors.primary,
                    tooltip: loc.copyPath,
                    onPressed: () => _copyPath(context, info.path),
                  ),
                  if (showOpen)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 20),
                      color: colors.primary,
                      tooltip: loc.openFolder,
                      onPressed: () => _openFolder(context, info.path),
                    ),
                ] else
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
