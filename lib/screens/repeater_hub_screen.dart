import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../services/repeater_command_service.dart';
import 'repeater_neighbors_screen.dart';
import 'repeater_status_screen.dart';
import 'repeater_cli_screen.dart';
import 'repeater_settings_screen.dart';

class RepeaterHubScreen extends StatefulWidget {
  final Contact repeater;
  final String password;

  const RepeaterHubScreen({
    super.key,
    required this.repeater,
    required this.password,
  });

  @override
  State<RepeaterHubScreen> createState() => _RepeaterHubScreenState();
}

class _RepeaterHubScreenState extends State<RepeaterHubScreen> {
  bool _isSendingAdvert = false;
  RepeaterCommandService? _commandService;

  @override
  void initState() {
    super.initState();
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    _commandService = RepeaterCommandService(connector);
  }

  @override
  void dispose() {
    _commandService?.dispose();
    super.dispose();
  }

  Future<void> _sendAdvert() async {
    if (_isSendingAdvert) return;

    setState(() => _isSendingAdvert = true);

    try {
      // Send the advert command - this is fire-and-forget since the repeater
      // broadcasts an advert but may not send a text response back
      final connector = Provider.of<MeshCoreConnector>(context, listen: false);
      final repeater = connector.contacts.firstWhere(
        (c) => c.publicKeyHex == widget.repeater.publicKeyHex,
        orElse: () => widget.repeater,
      );

      // Prepare path and build the CLI command frame
      await connector.preparePathForContactSend(repeater);
      final timestampSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final frame = buildSendCliCommandFrame(
        repeater.publicKey,
        'advert',
        attempt: 0,
        timestampSeconds: timestampSeconds,
      );
      await connector.sendFrame(frame);

      // Brief delay to ensure frame is sent
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Advertisement command sent')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send advertisement: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingAdvert = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Repeater Management'),
            Text(
              widget.repeater.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
              // Repeater info card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.orange,
                        child: const Icon(Icons.cell_tower, size: 40, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.repeater.name,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.repeater.pathLabel,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      if (widget.repeater.hasLocation) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.repeater.latitude?.toStringAsFixed(4)}, ${widget.repeater.longitude?.toStringAsFixed(4)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Management Tools',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              // Advert button
              _buildManagementCard(
                context,
                icon: Icons.broadcast_on_personal,
                title: 'Send Advert',
                subtitle: 'Broadcast presence from this repeater',
                color: Colors.purple,
                onTap: _isSendingAdvert ? () {} : _sendAdvert,
                isLoading: _isSendingAdvert,
              ),
              const SizedBox(height: 12),
              // Status button
              _buildManagementCard(
                context,
                icon: Icons.analytics,
                title: 'Status',
                subtitle: 'View repeater status, stats, and neighbors',
                color: Colors.blue,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RepeaterStatusScreen(
                        repeater: widget.repeater,
                        password: widget.password,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              // Neighbors button
              _buildManagementCard(
                context,
                icon: Icons.hub,
                title: 'Neighbors',
                subtitle: 'View one-hop neighbors with signal strength',
                color: Colors.teal,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RepeaterNeighborsScreen(
                        repeater: widget.repeater,
                        password: widget.password,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              // CLI button
              _buildManagementCard(
                context,
                icon: Icons.terminal,
                title: 'CLI',
                subtitle: 'Send commands to the repeater',
                color: Colors.green,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RepeaterCliScreen(
                        repeater: widget.repeater,
                        password: widget.password,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              // Settings button
              _buildManagementCard(
                context,
                icon: Icons.settings,
                title: 'Settings',
                subtitle: 'Configure repeater parameters',
                color: Colors.orange,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RepeaterSettingsScreen(
                        repeater: widget.repeater,
                        password: widget.password,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildManagementCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: color,
                        ),
                      )
                    : Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
