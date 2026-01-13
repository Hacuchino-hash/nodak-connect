import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/ble_debug_log_service.dart';
import '../widgets/battery_indicator.dart';
import '../connector/meshcore_connector.dart';

/// Screen for viewing received packet log
class RxLogScreen extends StatefulWidget {
  const RxLogScreen({super.key});

  @override
  State<RxLogScreen> createState() => _RxLogScreenState();
}

class _RxLogScreenState extends State<RxLogScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connector = context.watch<MeshCoreConnector>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RX Log'),
        centerTitle: true,
        actions: [
          BatteryIndicator(connector: connector),
          IconButton(
            icon: Icon(_autoScroll ? Icons.lock : Icons.lock_open),
            tooltip: _autoScroll ? 'Auto-scroll enabled' : 'Auto-scroll disabled',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all',
            onPressed: () => _copyAll(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear log',
            onPressed: () => _clearLog(context),
          ),
        ],
      ),
      body: Consumer<BleDebugLogService>(
        builder: (context, logService, child) {
          final entries = logService.rawLogRxEntries;

          if (entries.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long,
                    size: 64,
                    color: colorScheme.onSurfaceVariant.withOpacity(0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No packets received yet',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Incoming packets will appear here',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            );
          }

          // Auto-scroll to bottom when new entries arrive
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_autoScroll && _scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _buildLogEntry(context, entry, index);
            },
          );
        },
      ),
    );
  }

  Widget _buildLogEntry(BuildContext context, BleRawLogRxEntry entry, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final timeStr = '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}.'
        '${(entry.timestamp.millisecond ~/ 10).toString().padLeft(2, '0')}';

    final hexData = entry.payload
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');

    final codeStr = entry.payload.isNotEmpty
        ? '0x${entry.payload[0].toRadixString(16).padLeft(2, '0').toUpperCase()}'
        : '??';

    return InkWell(
      onLongPress: () => _copyEntry(context, entry),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: index.isEven
              ? colorScheme.surfaceContainerLowest
              : colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  timeStr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'RX',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Code: $codeStr',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.payload.length} bytes',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              hexData,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colorScheme.onSurface,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _copyEntry(BuildContext context, BleRawLogRxEntry entry) {
    final hexData = entry.payload
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');

    Clipboard.setData(ClipboardData(text: hexData));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _copyAll(BuildContext context) {
    final logService = context.read<BleDebugLogService>();
    final entries = logService.rawLogRxEntries;

    final buffer = StringBuffer();
    for (final entry in entries) {
      final timeStr = entry.timestamp.toIso8601String();
      final hexData = entry.payload
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');
      buffer.writeln('[$timeStr] $hexData');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied ${entries.length} entries'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _clearLog(BuildContext context) {
    final logService = context.read<BleDebugLogService>();
    logService.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Log cleared'),
        duration: Duration(seconds: 1),
      ),
    );
  }
}
