import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../models/contact.dart';
import '../services/path_history_service.dart';
import 'path_selection_dialog.dart';

class PathManagementDialog {
  static Future<void> show(
    BuildContext context, {
    required Contact contact,
    String title = 'Path Management',
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => _PathManagementDialog(
        contact: contact,
        title: title,
      ),
    );
  }
}

class _PathManagementDialog extends StatelessWidget {
  final Contact contact;
  final String title;

  const _PathManagementDialog({
    required this.contact,
    required this.title,
  });

  Contact _resolveContact(MeshCoreConnector connector) {
    return connector.contacts.firstWhere(
      (c) => c.publicKeyHex == contact.publicKeyHex,
      orElse: () => contact,
    );
  }

  String _formatRelativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showFullPathDialog(BuildContext context, List<int> pathBytes) {
    if (pathBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Path details not available yet. Try sending a message to refresh.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final formattedPath = pathBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(',');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Full Path'),
        content: SelectableText(formattedPath),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _setCustomPath(
    BuildContext context,
    MeshCoreConnector connector,
    Contact currentContact,
  ) async {
    if (currentContact.pathLength > 0 && currentContact.path.isEmpty && connector.isConnected) {
      connector.getContacts();
    }

    final pathForInput = currentContact.pathIdList;
    final availableContacts = connector.contacts
        .where((c) => c.publicKeyHex != currentContact.publicKeyHex)
        .toList();

    final result = await PathSelectionDialog.show(
      context,
      availableContacts: availableContacts,
      initialPath: pathForInput.isEmpty ? null : pathForInput,
      title: 'Set Custom Path',
      currentPathLabel: currentContact.pathLabel,
      onRefresh: connector.isConnected ? connector.getContacts : null,
    );

    if (result != null && context.mounted) {
      await connector.setPathOverride(
        currentContact,
        pathLen: result.length,
        pathBytes: result,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Path set: ${result.length} ${result.length == 1 ? "hop" : "hops"}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MeshCoreConnector, PathHistoryService>(
      builder: (context, connector, pathService, _) {
        final currentContact = _resolveContact(connector);
        final paths = pathService.getRecentPaths(currentContact.publicKeyHex);

        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current path: ${currentContact.pathLabel}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                if (paths.isNotEmpty) ...[
                  const Text(
                    'Recent ACK Paths (tap to use):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  if (paths.length >= 100) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Path history is full. Remove entries to add new ones.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ...paths.map((path) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: path.wasFloodDiscovery ? Colors.blue : Colors.green,
                          child: Text(
                            '${path.hopCount}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        title: Text(
                          '${path.hopCount} ${path.hopCount == 1 ? 'hop' : 'hops'}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '${(path.tripTimeMs / 1000).toStringAsFixed(2)}s • ${_formatRelativeTime(path.timestamp)} • ${path.successCount} successes',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: 'Remove path',
                              onPressed: () async {
                                await pathService.removePathRecord(
                                  currentContact.publicKeyHex,
                                  path.pathBytes,
                                );
                              },
                            ),
                            path.wasFloodDiscovery
                                ? const Icon(Icons.waves, size: 16, color: Colors.grey)
                                : const Icon(Icons.route, size: 16, color: Colors.grey),
                          ],
                        ),
                        onLongPress: () => _showFullPathDialog(context, path.pathBytes),
                        onTap: () async {
                          if (path.pathBytes.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Path details not available yet. Try sending a message to refresh.'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            return;
                          }

                          final pathBytes = Uint8List.fromList(path.pathBytes);
                          final pathLength = path.pathBytes.length;

                          await connector.setPathOverride(
                            currentContact,
                            pathLen: pathLength,
                            pathBytes: pathBytes,
                          );

                          if (!context.mounted) return;
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Using ${path.hopCount} ${path.hopCount == 1 ? 'hop' : 'hops'} path'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                  const Divider(),
                ] else ...[
                  const Text('No path history yet.\nSend a message to discover paths.'),
                  const Divider(),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Path Actions:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 8),
                ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.purple,
                    child: Icon(Icons.edit_road, size: 16),
                  ),
                  title: const Text('Set Custom Path', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Manually specify routing path', style: TextStyle(fontSize: 11)),
                  onTap: () async {
                    await _setCustomPath(context, connector, currentContact);
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.clear_all, size: 16),
                  ),
                  title: const Text('Clear Path', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Force rediscovery on next send', style: TextStyle(fontSize: 11)),
                  onTap: () async {
                    await connector.clearContactPath(currentContact);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Path cleared. Next message will rediscover route.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.waves, size: 16),
                  ),
                  title: const Text('Force Flood Mode', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Use routing toggle in app bar', style: TextStyle(fontSize: 11)),
                  onTap: () async {
                    await connector.setPathOverride(currentContact, pathLen: -1);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Flood mode enabled. Toggle back via routing icon in app bar.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
