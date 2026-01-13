import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../utils/disconnect_navigation_mixin.dart';
import '../widgets/battery_indicator.dart';
import 'app_debug_log_screen.dart';
import 'ble_debug_log_screen.dart';
import 'rx_log_screen.dart';
import 'discover_nodes_screen.dart';
import 'trace_path_screen.dart';
import 'wardrive_screen.dart';

/// Tools hub screen with access to various diagnostic and utility tools
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen>
    with DisconnectNavigationMixin {
  @override
  Widget build(BuildContext context) {
    return Consumer<MeshCoreConnector>(
      builder: (context, connector, child) {
        if (!checkConnectionAndNavigate(connector)) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Tools'),
            centerTitle: true,
            actions: [
              BatteryIndicator(connector: connector),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionLabel(theme, 'Network Tools'),
                const SizedBox(height: 12),
                _buildToolCard(
                  context: context,
                  icon: Icons.search,
                  color: Colors.blue,
                  title: 'Discover Nearby Nodes',
                  subtitle: 'Scan for nodes on the mesh network',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DiscoverNodesScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildToolCard(
                  context: context,
                  icon: Icons.timeline,
                  color: Colors.green,
                  title: 'Trace Path',
                  subtitle: 'Visualize route to a contact',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TracePathScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionLabel(theme, 'Coverage'),
                const SizedBox(height: 12),
                _buildToolCard(
                  context: context,
                  icon: Icons.drive_eta,
                  color: Colors.purple,
                  title: 'Wardrive',
                  subtitle: 'Map network coverage while moving',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const WardriveScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionLabel(theme, 'Debug Logs'),
                const SizedBox(height: 12),
                _buildToolCard(
                  context: context,
                  icon: Icons.receipt_long,
                  color: Colors.orange,
                  title: 'RX Log',
                  subtitle: 'View received packets',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RxLogScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildToolCard(
                  context: context,
                  icon: Icons.bluetooth,
                  color: Colors.grey,
                  title: 'BLE Debug Log',
                  subtitle: 'View Bluetooth frame traffic',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BleDebugLogScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildToolCard(
                  context: context,
                  icon: Icons.article,
                  color: Colors.grey,
                  title: 'App Debug Log',
                  subtitle: 'View application debug messages',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AppDebugLogScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionLabel(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildToolCard({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.15),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
