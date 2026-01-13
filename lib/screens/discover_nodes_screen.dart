import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../widgets/battery_indicator.dart';

/// Screen for discovering nearby mesh nodes
class DiscoverNodesScreen extends StatefulWidget {
  const DiscoverNodesScreen({super.key});

  @override
  State<DiscoverNodesScreen> createState() => _DiscoverNodesScreenState();
}

class _DiscoverNodesScreenState extends State<DiscoverNodesScreen> {
  bool _showAlreadyAdded = true;
  int? _typeFilter; // null = all, or specific advType value

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Consumer<MeshCoreConnector>(
      builder: (context, connector, child) {
        final contacts = connector.contacts;

        // Filter based on toggle and type
        var displayedContacts = _showAlreadyAdded
            ? contacts
            : contacts.where((c) => !_isInContacts(c, contacts)).toList();

        // Apply type filter
        if (_typeFilter != null) {
          displayedContacts = displayedContacts.where((c) => c.type == _typeFilter).toList();
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(_typeFilter == null
                ? 'Discover Nodes'
                : 'Discover ${_getTypeName(_typeFilter!)}s'),
            centerTitle: true,
            actions: [
              BatteryIndicator(connector: connector),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh contacts',
                onPressed: () => connector.refreshContacts(),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filter',
                onSelected: (value) {
                  if (value == 'toggle_added') {
                    setState(() => _showAlreadyAdded = !_showAlreadyAdded);
                  } else if (value == 'filter_all') {
                    setState(() => _typeFilter = null);
                  } else if (value == 'filter_chat') {
                    setState(() => _typeFilter = advTypeChat);
                  } else if (value == 'filter_repeater') {
                    setState(() => _typeFilter = advTypeRepeater);
                  } else if (value == 'filter_room') {
                    setState(() => _typeFilter = advTypeRoom);
                  } else if (value == 'filter_sensor') {
                    setState(() => _typeFilter = advTypeSensor);
                  }
                },
                itemBuilder: (context) => [
                  CheckedPopupMenuItem<String>(
                    value: 'toggle_added',
                    checked: _showAlreadyAdded,
                    child: const Text('Show already added'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    enabled: false,
                    child: Text('Node Type', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'filter_all',
                    checked: _typeFilter == null,
                    child: const Text('All Types'),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'filter_chat',
                    checked: _typeFilter == advTypeChat,
                    child: const Text('Chat Nodes'),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'filter_repeater',
                    checked: _typeFilter == advTypeRepeater,
                    child: const Text('Repeaters Only'),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'filter_room',
                    checked: _typeFilter == advTypeRoom,
                    child: const Text('Rooms Only'),
                  ),
                  CheckedPopupMenuItem<String>(
                    value: 'filter_sensor',
                    checked: _typeFilter == advTypeSensor,
                    child: const Text('Sensors Only'),
                  ),
                ],
              ),
            ],
          ),
          body: connector.isLoadingContacts
              ? const Center(child: CircularProgressIndicator())
              : displayedContacts.isEmpty
                  ? _buildEmptyState(context)
                  : _buildNodeList(context, displayedContacts, connector),
        );
      },
    );
  }

  bool _isInContacts(Contact contact, List<Contact> allContacts) {
    // All contacts in the list are "known" since they come from the device
    return true;
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: colorScheme.onSurfaceVariant.withOpacity(0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'No nodes discovered yet',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Nodes will appear as they advertise',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              final connector = context.read<MeshCoreConnector>();
              connector.refreshContacts();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeList(
    BuildContext context,
    List<Contact> contacts,
    MeshCoreConnector connector,
  ) {
    // Sort by last seen (most recent first)
    final sortedContacts = List<Contact>.from(contacts)
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedContacts.length,
      itemBuilder: (context, index) {
        final contact = sortedContacts[index];
        return _buildNodeTile(context, contact, connector);
      },
    );
  }

  Widget _buildNodeTile(
    BuildContext context,
    Contact contact,
    MeshCoreConnector connector,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final typeIcon = _getTypeIcon(contact.type);
    final typeColor = _getTypeColor(contact.type);
    final timeSinceLastSeen = _formatTimeSince(contact.lastSeen);
    final pathLabel = _getPathLabel(contact);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: InkWell(
        onTap: () => _showNodeDetails(context, contact),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: typeColor.withOpacity(0.15),
                child: Icon(typeIcon, color: typeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.name.isEmpty ? 'Unknown' : contact.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _getTypeName(contact.type),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: typeColor,
                          ),
                        ),
                        if (pathLabel.isNotEmpty) ...[
                          Text(
                            ' • ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            pathLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timeSinceLastSeen,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (contact.hasLocation) ...[
                    const SizedBox(height: 2),
                    Icon(
                      Icons.location_on,
                      size: 14,
                      color: colorScheme.primary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNodeDetails(BuildContext context, Contact contact) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getTypeColor(contact.type).withOpacity(0.15),
                    radius: 24,
                    child: Icon(
                      _getTypeIcon(contact.type),
                      color: _getTypeColor(contact.type),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.name.isEmpty ? 'Unknown' : contact.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _getTypeName(contact.type),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _getTypeColor(contact.type),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildDetailRow(
                context,
                'Public Key',
                contact.publicKeyHex.substring(0, 16) + '...',
              ),
              _buildDetailRow(
                context,
                'Last Seen',
                _formatTimeSince(contact.lastSeen),
              ),
              _buildDetailRow(
                context,
                'Path',
                _getPathLabel(contact).isEmpty ? 'Unknown' : _getPathLabel(contact),
              ),
              if (contact.hasLocation)
                _buildDetailRow(
                  context,
                  'Location',
                  '${contact.latitude?.toStringAsFixed(4)}, ${contact.longitude?.toStringAsFixed(4)}',
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Navigate to chat with this contact
                  },
                  child: const Text('Open Chat'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getTypeIcon(int type) {
    switch (type) {
      case advTypeChat:
        return Icons.person;
      case advTypeRepeater:
        return Icons.router;
      case advTypeRoom:
        return Icons.meeting_room;
      case advTypeSensor:
        return Icons.sensors;
      default:
        return Icons.device_unknown;
    }
  }

  Color _getTypeColor(int type) {
    switch (type) {
      case advTypeChat:
        return Colors.blue;
      case advTypeRepeater:
        return Colors.green;
      case advTypeRoom:
        return Colors.purple;
      case advTypeSensor:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getTypeName(int type) {
    switch (type) {
      case advTypeChat:
        return 'Chat';
      case advTypeRepeater:
        return 'Repeater';
      case advTypeRoom:
        return 'Room';
      case advTypeSensor:
        return 'Sensor';
      default:
        return 'Unknown';
    }
  }

  String _getPathLabel(Contact contact) {
    if (contact.pathLength < 0) {
      return 'Flood';
    } else if (contact.pathLength == 0) {
      return 'Direct';
    } else {
      return '${contact.pathLength} hops';
    }
  }

  String _formatTimeSince(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}
