import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../models/contact_group.dart';
import '../services/storage_service.dart';
import '../storage/contact_group_store.dart';
import '../utils/contact_search.dart';
import '../utils/dialog_utils.dart';
import '../utils/disconnect_navigation_mixin.dart';
import '../utils/emoji_utils.dart';
import '../utils/route_transitions.dart';
import '../widgets/battery_indicator.dart';
import '../widgets/list_filter_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/quick_switch_bar.dart';
import '../widgets/repeater_login_dialog.dart';
import '../widgets/unread_badge.dart';
import 'channels_screen.dart';
import 'chat_screen.dart';
import 'map_screen.dart';
import 'repeater_hub_screen.dart';
import 'settings_screen.dart';
import 'tools_screen.dart';

class ContactsScreen extends StatefulWidget {
  final bool hideBackButton;

  const ContactsScreen({
    super.key,
    this.hideBackButton = false,
  });

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen>
    with DisconnectNavigationMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  ContactSortOption _sortOption = ContactSortOption.lastSeen;
  bool _showUnreadOnly = false;
  ContactTypeFilter _typeFilter = ContactTypeFilter.all;
  final ContactGroupStore _groupStore = ContactGroupStore();
  List<ContactGroup> _groups = [];
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    final groups = await _groupStore.loadGroups();
    if (!mounted) return;
    setState(() {
      _groups = groups;
    });
  }

  Future<void> _saveGroups() async {
    await _groupStore.saveGroups(_groups);
  }

  @override
  Widget build(BuildContext context) {
    final connector = context.watch<MeshCoreConnector>();

    // Auto-navigate back to scanner if disconnected
    if (!checkConnectionAndNavigate(connector)) {
      return const SizedBox.shrink();
    }

    final allowBack = !connector.isConnected;
    return PopScope(
      canPop: allowBack,
      child: Scaffold(
        appBar: AppBar(
          leading: BatteryIndicator(connector: connector),
          title: const Text('Contacts'),
          centerTitle: true,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              tooltip: 'Disconnect',
              onPressed: () => _disconnect(context, connector),
            ),
            IconButton(
              icon: const Icon(Icons.construction),
              tooltip: 'Tools',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ToolsScreen()),
              ),
            ),
          ],
        ),
        body: _buildContactsBody(context, connector),
        bottomNavigationBar: SafeArea(
          top: false,
          child: QuickSwitchBar(
            selectedIndex: 1,
            onDestinationSelected: (index) => _handleQuickSwitch(index, context),
          ),
        ),
      ),
    );
  }

  Future<void> _disconnect(
    BuildContext context,
    MeshCoreConnector connector,
  ) async {
    await showDisconnectDialog(context, connector);
  }

  Widget _buildFilterButton(BuildContext context, MeshCoreConnector connector) {
    return ContactsFilterMenu(
      sortOption: _sortOption,
      typeFilter: _typeFilter,
      showUnreadOnly: _showUnreadOnly,
      onSortChanged: (value) {
        setState(() {
          _sortOption = value;
        });
      },
      onTypeFilterChanged: (value) {
        setState(() {
          _typeFilter = value;
        });
      },
      onUnreadOnlyChanged: (value) {
        setState(() {
          _showUnreadOnly = value;
        });
      },
      onNewGroup: () => _showGroupEditor(context, connector.contacts),
    );
  }

  Widget _buildContactsBody(BuildContext context, MeshCoreConnector connector) {
    final contacts = connector.contacts;

    if (contacts.isEmpty && connector.isLoadingContacts && _groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (contacts.isEmpty && _groups.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        title: 'No contacts yet',
        subtitle: 'Contacts will appear when devices advertise',
      );
    }

    final filteredAndSorted = _filterAndSortContacts(contacts, connector);
    final filteredGroups =
        _showUnreadOnly ? const <ContactGroup>[] : _filterAndSortGroups(_groups, contacts);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search contacts...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    ),
                  _buildFilterButton(context, connector),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                if (!mounted) return;
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              });
            },
          ),
        ),
        Expanded(
          child: filteredAndSorted.isEmpty && filteredGroups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        _showUnreadOnly
                            ? 'No unread contacts'
                            : 'No contacts or groups found',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => connector.getContacts(),
                  child: ListView.builder(
                    itemCount: filteredGroups.length + filteredAndSorted.length,
                    itemBuilder: (context, index) {
                      if (index < filteredGroups.length) {
                        final group = filteredGroups[index];
                        return _buildGroupTile(context, group, contacts);
                      }
                      final contact = filteredAndSorted[index - filteredGroups.length];
                      final unreadCount = connector.getUnreadCountForContact(contact);
                      return _ContactTile(
                        contact: contact,
                        lastSeen: _resolveLastSeen(contact),
                        unreadCount: unreadCount,
                        onTap: () => _openChat(context, contact),
                        onLongPress: () => _showContactOptions(context, connector, contact),
                        onMenuAction: (action) => _handleMenuAction(context, connector, contact, action),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  List<ContactGroup> _filterAndSortGroups(List<ContactGroup> groups, List<Contact> contacts) {
    final query = _searchQuery.trim().toLowerCase();
    final contactsByKey = <String, Contact>{};
    for (final contact in contacts) {
      contactsByKey[contact.publicKeyHex] = contact;
    }

    final filtered = groups.where((group) {
      if (query.isEmpty) return true;
      if (group.name.toLowerCase().contains(query)) return true;
      for (final key in group.memberKeys) {
        final contact = contactsByKey[key];
        if (contact != null && matchesContactQuery(contact, query)) return true;
      }
      return false;
    }).where((group) {
      if (_typeFilter == ContactTypeFilter.all) return true;
      for (final key in group.memberKeys) {
        final contact = contactsByKey[key];
        if (contact != null && _matchesTypeFilter(contact)) return true;
      }
      return false;
    }).toList();

    filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return filtered;
  }

  List<Contact> _filterAndSortContacts(List<Contact> contacts, MeshCoreConnector connector) {
    var filtered = contacts.where((contact) {
      if (_searchQuery.isEmpty) return true;
      return matchesContactQuery(contact, _searchQuery);
    }).toList();

    if (_typeFilter != ContactTypeFilter.all) {
      filtered = filtered.where(_matchesTypeFilter).toList();
    }

    if (_showUnreadOnly) {
      filtered = filtered.where((contact) {
        return connector.getUnreadCountForContact(contact) > 0;
      }).toList();
    }

    switch (_sortOption) {
      case ContactSortOption.lastSeen:
        filtered.sort((a, b) => _resolveLastSeen(b).compareTo(_resolveLastSeen(a)));
        break;
      case ContactSortOption.recentMessages:
        filtered.sort((a, b) {
          final aMessages = connector.getMessages(a);
          final bMessages = connector.getMessages(b);
          final aLastMsg = aMessages.isEmpty ? DateTime(1970) : aMessages.last.timestamp;
          final bLastMsg = bMessages.isEmpty ? DateTime(1970) : bMessages.last.timestamp;
          return bLastMsg.compareTo(aLastMsg);
        });
        break;
      case ContactSortOption.name:
        filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
    }

    return filtered;
  }

  bool _matchesTypeFilter(Contact contact) {
    switch (_typeFilter) {
      case ContactTypeFilter.all:
        return true;
      case ContactTypeFilter.users:
        return contact.type == advTypeChat;
      case ContactTypeFilter.repeaters:
        return contact.type == advTypeRepeater;
      case ContactTypeFilter.rooms:
        return contact.type == advTypeRoom;
      case ContactTypeFilter.hideRepeaters:
        return contact.type != advTypeRepeater;
    }
  }

  DateTime _resolveLastSeen(Contact contact) {
    if (contact.type != advTypeChat) return contact.lastSeen;
    return contact.lastMessageAt.isAfter(contact.lastSeen)
        ? contact.lastMessageAt
        : contact.lastSeen;
  }

  Widget _buildGroupTile(BuildContext context, ContactGroup group, List<Contact> contacts) {
    final memberContacts = _resolveGroupContacts(group, contacts);
    final subtitle = _formatGroupMembers(memberContacts);
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.teal,
        child: Icon(Icons.group, color: Colors.white, size: 20),
      ),
      title: Text(group.name),
      subtitle: Text(subtitle),
      trailing: Text(
        memberContacts.length.toString(),
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      onTap: () => _showGroupOptions(context, group, contacts),
      onLongPress: () => _showGroupOptions(context, group, contacts),
    );
  }

  List<Contact> _resolveGroupContacts(ContactGroup group, List<Contact> contacts) {
    final byKey = <String, Contact>{};
    for (final contact in contacts) {
      byKey[contact.publicKeyHex] = contact;
    }
    final resolved = <Contact>[];
    for (final key in group.memberKeys) {
      final contact = byKey[key];
      if (contact != null) {
        resolved.add(contact);
      }
    }
    resolved.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return resolved;
  }

  String _formatGroupMembers(List<Contact> members) {
    if (members.isEmpty) return 'No members';
    final names = members.map((c) => c.name).toList();
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} +${names.length - 2}';
  }

  void _openChat(BuildContext context, Contact contact) {
    // Check if this is a repeater
    if (contact.type == advTypeRepeater) {
      _showRepeaterLogin(context, contact);
    } else {
      context.read<MeshCoreConnector>().markContactRead(contact.publicKeyHex);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ChatScreen(contact: contact)),
      );
    }
  }

  void _handleQuickSwitch(int index, BuildContext context) {
    if (index == 1) return; // Already on Contacts
    switch (index) {
      case 0:
        // Settings
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          buildQuickSwitchRoute(
            const ChannelsScreen(hideBackButton: true),
          ),
        );
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          buildQuickSwitchRoute(
            const MapScreen(hideBackButton: true),
          ),
        );
        break;
    }
  }

  Future<void> _showRepeaterLogin(BuildContext context, Contact repeater) async {
    final connector = context.read<MeshCoreConnector>();
    final storage = StorageService();

    // Check if per-repeater auto-login is enabled
    final isAutoLoginEnabled = await storage.isRepeaterAutoLoginEnabled(repeater.publicKeyHex);
    if (isAutoLoginEnabled) {
      final savedPassword = await storage.getRepeaterPassword(repeater.publicKeyHex);
      // Use saved password or empty string for guest login
      final passwordToUse = savedPassword ?? '';

      // Show brief loading indicator
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(child: Text('Logging into ${repeater.name}...')),
            ],
          ),
        ),
      );

      // Attempt auto-login
      try {
        final selection = await connector.preparePathForContactSend(repeater);
        final loginFrame = buildSendLoginFrame(repeater.publicKey, passwordToUse);
        final timeoutMs = connector.calculateTimeout(
          pathLength: selection.useFlood ? -1 : selection.hopCount,
          messageBytes: loginFrame.length,
        );
        final timeout = Duration(milliseconds: timeoutMs);

        bool? loginResult;
        for (int attempt = 0; attempt < 3; attempt++) {
          await connector.sendFrame(loginFrame);
          loginResult = await _awaitLoginResponse(connector, repeater, timeout);
          if (loginResult == true || loginResult == false) break;
        }

        if (!context.mounted) return;
        Navigator.pop(context); // Close loading dialog

        if (loginResult == true) {
          // Auto-login successful, navigate to repeater hub
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RepeaterHubScreen(
                repeater: repeater,
                password: passwordToUse,
              ),
            ),
          );
          return;
        }

        // Auto-login failed, show options dialog
        if (context.mounted) {
          _showAutoLoginFailedDialog(context, connector, repeater);
          return;
        }
      } catch (e) {
        if (context.mounted) {
          Navigator.pop(context); // Close loading dialog
          _showAutoLoginFailedDialog(context, connector, repeater);
          return;
        }
      }
    }

    // Show manual login dialog
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => RepeaterLoginDialog(
        repeater: repeater,
        onLogin: (password) {
          // Navigate to repeater hub screen after successful login
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RepeaterHubScreen(
                repeater: repeater,
                password: password,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAutoLoginFailedDialog(
    BuildContext context,
    MeshCoreConnector connector,
    Contact repeater,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Auto-Login Failed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Could not connect to ${repeater.name}.'),
            const SizedBox(height: 16),
            const Text('Would you like to:'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Switch to flood mode and retry login dialog
              await connector.setPathOverride(repeater, pathLen: -1);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Switched to flood mode')),
              );
              // Reopen login dialog
              showDialog(
                context: context,
                builder: (context) => RepeaterLoginDialog(
                  repeater: repeater,
                  onLogin: (password) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RepeaterHubScreen(
                          repeater: repeater,
                          password: password,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            child: const Text('Use Flood Mode'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _showSetPathDialog(context, connector, repeater);
            },
            child: const Text('Set Path'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // Just open normal login dialog
              showDialog(
                context: context,
                builder: (context) => RepeaterLoginDialog(
                  repeater: repeater,
                  onLogin: (password) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RepeaterHubScreen(
                          repeater: repeater,
                          password: password,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _awaitLoginResponse(
    MeshCoreConnector connector,
    Contact repeater,
    Duration timeout,
  ) async {
    final completer = Completer<bool?>();
    Timer? timer;
    StreamSubscription<Uint8List>? subscription;
    final targetPrefix = repeater.publicKey.sublist(0, 6);

    subscription = connector.receivedFrames.listen((frame) {
      if (frame.isEmpty) return;
      final code = frame[0];
      if (code != pushCodeLoginSuccess && code != pushCodeLoginFail) return;
      if (frame.length < 8) return;
      final prefix = frame.sublist(2, 8);
      if (!listEquals(prefix, targetPrefix)) return;

      completer.complete(code == pushCodeLoginSuccess);
      subscription?.cancel();
      timer?.cancel();
    });

    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(null);
        subscription?.cancel();
      }
    });

    final result = await completer.future;
    timer.cancel();
    await subscription.cancel();
    return result;
  }

  void _showGroupOptions(BuildContext context, ContactGroup group, List<Contact> contacts) {
    final members = _resolveGroupContacts(group, contacts);
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit Group'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showGroupEditor(context, contacts, group: group);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete Group', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDeleteGroup(context, group);
                },
              ),
              if (members.isNotEmpty) const Divider(),
              ...members.map((member) {
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(member.name),
                  subtitle: Text(member.typeLabel),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openChat(context, member);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteGroup(BuildContext context, ContactGroup group) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Remove "${group.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() {
                _groups.removeWhere((g) => g.name == group.name);
              });
              await _saveGroups();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showGroupEditor(
    BuildContext context,
    List<Contact> contacts, {
    ContactGroup? group,
  }) {
    final isEditing = group != null;
    final nameController = TextEditingController(text: group?.name ?? '');
    final selectedKeys = <String>{...group?.memberKeys ?? []};
    String filterQuery = '';
    final sortedContacts = List<Contact>.from(contacts)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) {
          final filteredContacts = filterQuery.isEmpty
              ? sortedContacts
              : sortedContacts
                  .where((contact) => matchesContactQuery(contact, filterQuery))
                  .toList();
          return AlertDialog(
            title: Text(isEditing ? 'Edit Group' : 'New Group'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Group name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Filter contacts...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        filterQuery = value.toLowerCase();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 240,
                    child: filteredContacts.isEmpty
                        ? const Center(child: Text('No contacts match your filter'))
                        : ListView.builder(
                            itemCount: filteredContacts.length,
                            itemBuilder: (context, index) {
                              final contact = filteredContacts[index];
                              final isSelected = selectedKeys.contains(contact.publicKeyHex);
                              return CheckboxListTile(
                                value: isSelected,
                                title: Text(contact.name),
                                subtitle: Text(contact.typeLabel),
                                onChanged: (value) {
                                  setDialogState(() {
                                    if (value == true) {
                                      selectedKeys.add(contact.publicKeyHex);
                                    } else {
                                      selectedKeys.remove(contact.publicKeyHex);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Group name is required')),
                    );
                    return;
                  }
                  final exists = _groups.any((g) {
                    if (isEditing && g.name == group.name) return false;
                    return g.name.toLowerCase() == name.toLowerCase();
                  });
                  if (exists) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Group "$name" already exists')),
                    );
                    return;
                  }
                  setState(() {
                    if (isEditing) {
                      final index = _groups.indexWhere((g) => g.name == group.name);
                      if (index != -1) {
                        _groups[index] = ContactGroup(
                          name: name,
                          memberKeys: selectedKeys.toList(),
                        );
                      }
                    } else {
                      _groups.add(ContactGroup(name: name, memberKeys: selectedKeys.toList()));
                    }
                  });
                  await _saveGroups();
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: Text(isEditing ? 'Save' : 'Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showContactOptions(
    BuildContext context,
    MeshCoreConnector connector,
    Contact contact,
  ) {
    final isRepeater = contact.type == advTypeRepeater;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRepeater)
              ListTile(
                leading: const Icon(Icons.cell_tower, color: Colors.orange),
                title: const Text('Manage Repeater'),
                onTap: () {
                  Navigator.pop(context);
                  _showRepeaterLogin(context, contact);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.chat),
                title: const Text('Open Chat'),
                onTap: () {
                  Navigator.pop(context);
                  _openChat(context, contact);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Contact', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, connector, contact);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    MeshCoreConnector connector,
    Contact contact,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Remove ${contact.name} from contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              connector.removeContact(contact);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(
    BuildContext context,
    MeshCoreConnector connector,
    Contact contact,
    String action,
  ) {
    switch (action) {
      case 'set_path':
        _showSetPathDialog(context, connector, contact);
        break;
      case 'clear_path':
        _showClearPathDialog(context, connector, contact);
        break;
      case 'auto_login':
        _showAutoLoginSettings(context, contact);
        break;
    }
  }

  Future<void> _showSetPathDialog(
    BuildContext context,
    MeshCoreConnector connector,
    Contact contact,
  ) async {
    // Get available repeaters
    final repeaters = connector.contacts
        .where((c) => c.type == advTypeRepeater)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (repeaters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No repeaters available')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Set Path to ${contact.name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select a repeater to route through:'),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: repeaters.length,
                  itemBuilder: (context, index) {
                    final repeater = repeaters[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.orange,
                        child: Icon(Icons.cell_tower, color: Colors.white, size: 20),
                      ),
                      title: Text(repeater.name),
                      subtitle: Text(repeater.pathLabel),
                      onTap: () async {
                        Navigator.pop(dialogContext);
                        // Set path through the selected repeater (1 hop)
                        // Path bytes are the repeater's public key prefix (6 bytes)
                        final pathBytes = Uint8List.fromList(repeater.publicKey.sublist(0, 6));
                        await connector.setPathOverride(
                          contact,
                          pathLen: 1,
                          pathBytes: pathBytes,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Path set via ${repeater.name}')),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showClearPathDialog(
    BuildContext context,
    MeshCoreConnector connector,
    Contact contact,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Clear Path to ${contact.name}'),
        content: const Text('This will reset to auto mode (use device path or flood).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Clear path override by setting pathLen to null
              await connector.setPathOverride(contact, pathLen: null);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Path cleared for ${contact.name}')),
                );
              }
            },
            child: const Text('Clear Path'),
          ),
        ],
      ),
    );
  }

  void _showAutoLoginSettings(BuildContext context, Contact repeater) {
    final storage = StorageService();

    showDialog(
      context: context,
      builder: (dialogContext) => FutureBuilder(
        future: Future.wait([
          storage.isRepeaterAutoLoginEnabled(repeater.publicKeyHex),
          storage.getRepeaterPassword(repeater.publicKeyHex),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }

          final isEnabled = snapshot.data![0] as bool;
          final hasSavedPassword = (snapshot.data![1] as String?) != null;

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text('Auto-Login: ${repeater.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Enable Auto-Login'),
                    subtitle: Text(
                      hasSavedPassword
                          ? 'Password saved'
                          : 'No password saved - will try guest login',
                    ),
                    value: isEnabled,
                    onChanged: (value) async {
                      await storage.setRepeaterAutoLogin(
                          repeater.publicKeyHex, value);
                      setDialogState(() {});
                      // Rebuild the future
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                        _showAutoLoginSettings(context, repeater);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  if (hasSavedPassword)
                    ListTile(
                      leading: const Icon(Icons.delete, color: Colors.red),
                      title: const Text('Clear Saved Password',
                          style: TextStyle(color: Colors.red)),
                      onTap: () async {
                        await storage.removeRepeaterPassword(repeater.publicKeyHex);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Saved password removed')),
                          );
                        }
                      },
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final Contact contact;
  final DateTime lastSeen;
  final int unreadCount;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(String action) onMenuAction;

  const _ContactTile({
    required this.contact,
    required this.lastSeen,
    required this.unreadCount,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuAction,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getTypeColor(contact.type),
        child: _buildContactAvatar(contact),
      ),
      title: Text(contact.name),
      subtitle: Text('${contact.typeLabel} • ${contact.pathLabel}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (unreadCount > 0) ...[
                UnreadBadge(count: unreadCount),
                const SizedBox(height: 4),
              ],
              Text(
                _formatLastSeen(lastSeen),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              if (contact.hasLocation)
                Icon(Icons.location_on, size: 14, color: Colors.grey[400]),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: onMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'set_path',
                child: ListTile(
                  leading: Icon(Icons.route),
                  title: Text('Set Path'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'clear_path',
                child: ListTile(
                  leading: Icon(Icons.clear),
                  title: Text('Clear Path'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              if (contact.type == advTypeRepeater) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'auto_login',
                  child: ListTile(
                    leading: Icon(Icons.login),
                    title: Text('Auto-Login Settings'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  Widget _buildContactAvatar(Contact contact) {
    final emoji = firstEmoji(contact.name);
    if (emoji != null) {
      return Text(
        emoji,
        style: const TextStyle(fontSize: 18),
      );
    }
    return Icon(_getTypeIcon(contact.type), color: Colors.white, size: 20);
  }

  IconData _getTypeIcon(int type) {
    switch (type) {
      case advTypeChat:
        return Icons.chat;
      case advTypeRepeater:
        return Icons.cell_tower;
      case advTypeRoom:
        return Icons.group;
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
        return Colors.orange;
      case advTypeRoom:
        return Colors.purple;
      case advTypeSensor:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.isNegative || diff.inMinutes < 5) return 'Last seen now';
    if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes} mins ago';
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      return hours == 1 ? 'Last seen 1 hour ago' : 'Last seen $hours hours ago';
    }
    final days = diff.inDays;
    return days == 1 ? 'Last seen 1 day ago' : 'Last seen $days days ago';
  }
}
