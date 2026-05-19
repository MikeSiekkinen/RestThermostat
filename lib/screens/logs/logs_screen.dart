import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/app_logger.dart';
import '../../theme/typography.dart';

/// Diagnostic logs viewer per DESIGN §15.2 (Settings → View logs).
///
/// Renders the [AppLogger]'s in-memory ring buffer as a monospace scrollable
/// list, oldest-at-top / newest-at-bottom. The list auto-scrolls to the
/// bottom on first show so the most recent activity is visible.
///
/// Action bar provides Copy / Share / Clear:
/// - **Copy**: dumps the full log as plain text via [Clipboard].
/// - **Share**: hands the same text to the platform share sheet
///   (`share_plus`).
/// - **Clear**: confirmation dialog → [AppLogger.clear].
class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Newest-at-the-bottom per DESIGN §15.2 — jump once after the first
    // build so the user lands on the most recent activity.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _formatEntries(List<LogEntry> entries) {
    final fmt = DateFormat.Hms();
    return entries
        .map(
          (e) =>
              '${fmt.format(e.timestamp)} ${e.level.name.toUpperCase()} ${e.message}',
        )
        .join('\n');
  }

  Future<void> _onCopy(BuildContext context, List<LogEntry> entries) async {
    final text = _formatEntries(entries);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Logs copied to clipboard.')));
  }

  Future<void> _onShare(List<LogEntry> entries) async {
    final text = _formatEntries(entries);
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _onClear(BuildContext context) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Clear logs?'),
            content: const Text(
              'This removes all in-memory log entries. The buffer will start '
              'fresh from the next event.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    ref.read(appLoggerProvider).clear();
  }

  @override
  Widget build(BuildContext context) {
    final logger = ref.watch(appLoggerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostic logs'),
        actions: [
          ValueListenableBuilder<List<LogEntry>>(
            valueListenable: logger.notifier,
            builder: (context, entries, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Copy to clipboard',
                    icon: const Icon(Icons.copy),
                    onPressed: entries.isEmpty
                        ? null
                        : () => _onCopy(context, entries),
                  ),
                  IconButton(
                    tooltip: 'Share',
                    icon: const Icon(Icons.share),
                    onPressed: entries.isEmpty ? null : () => _onShare(entries),
                  ),
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: entries.isEmpty ? null : () => _onClear(context),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<List<LogEntry>>(
          valueListenable: logger.notifier,
          builder: (context, entries, _) {
            if (entries.isEmpty) {
              return const Center(child: Text('No log entries yet.'));
            }
            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: entries.length,
              itemBuilder: (context, i) => _LogRow(entry: entries[i]),
            );
          },
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  const _LogRow({required this.entry});

  static final DateFormat _timeFormat = DateFormat.Hms();

  Color _colorFor(LogLevel level, ColorScheme scheme) {
    switch (level) {
      case LogLevel.info:
        return scheme.primary;
      case LogLevel.warn:
        return Colors.amber;
      case LogLevel.error:
        return scheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final levelColor = _colorFor(entry.level, scheme);
    // The `labelSmall` style is uppercase-tracked for pill text; loosen the
    // letter-spacing here so a long monospace log line stays legible.
    final monoStyle = EmberTypography.labelSmall().copyWith(letterSpacing: 0.2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_timeFormat.format(entry.timestamp), style: monoStyle),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              entry.level.name.toUpperCase(),
              style: monoStyle.copyWith(color: levelColor),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(entry.message, style: monoStyle)),
        ],
      ),
    );
  }
}
