import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../services/map_tile_cache_service.dart';
import '../widgets/battery_indicator.dart';

/// Screen for tracing the path to a contact with SNR measurements
class TracePathScreen extends StatefulWidget {
  const TracePathScreen({super.key});

  @override
  State<TracePathScreen> createState() => _TracePathScreenState();
}

class _TracePathScreenState extends State<TracePathScreen> {
  bool _mapMode = false;
  final List<Contact> _selectedPath = [];
  bool _isTracing = false;
  TracePathResult? _lastTraceResult;
  String? _traceError;
  StreamSubscription<TracePathResult>? _traceSubscription;
  int? _pendingTraceTag;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final connector = context.read<MeshCoreConnector>();
      _traceSubscription = connector.traceResults.listen(_onTraceResult);
    });
  }

  @override
  void dispose() {
    _traceSubscription?.cancel();
    super.dispose();
  }

  void _onTraceResult(TracePathResult result) {
    if (_pendingTraceTag != null && result.tag == _pendingTraceTag) {
      setState(() {
        _lastTraceResult = result;
        _isTracing = false;
        _traceError = null;
        _pendingTraceTag = null;
      });
    }
  }

  /// Build the path bytes from selected contacts.
  /// The firmware handles the return path automatically - the last node
  /// in the path sends the PUSH_CODE_TRACE_DATA response directly back.
  Uint8List _buildPathBytes() {
    if (_selectedPath.isEmpty) {
      return Uint8List(0);
    }

    // Build path from first byte (hash) of each contact's public key
    final pathBytes = Uint8List(_selectedPath.length);
    for (int i = 0; i < _selectedPath.length; i++) {
      pathBytes[i] = _selectedPath[i].publicKey[0];
    }

    return pathBytes;
  }

  Future<void> _startTrace(MeshCoreConnector connector) async {
    if (_selectedPath.isEmpty) {
      setState(() {
        _traceError = 'Please select at least one node in the path';
      });
      return;
    }

    // Build path bytes (firmware handles return automatically)
    final pathBytes = _buildPathBytes();

    setState(() {
      _isTracing = true;
      _lastTraceResult = null;
      _traceError = null;
    });

    try {
      _pendingTraceTag = await connector.sendTracePath(pathBytes);

      // Set a timeout for the trace response
      Future.delayed(const Duration(seconds: 30), () {
        if (_isTracing && _pendingTraceTag != null && mounted) {
          setState(() {
            _isTracing = false;
            _traceError = 'Trace timed out - no response received';
            _pendingTraceTag = null;
          });
        }
      });
    } catch (e) {
      setState(() {
        _isTracing = false;
        _traceError = 'Failed to send trace: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MeshCoreConnector>(
      builder: (context, connector, child) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        // Get repeaters for path building
        final repeaters = connector.contacts
            .where((c) => c.type == advTypeRepeater || c.type == advTypeRoom)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        // Get all contacts for destination selection
        final allContacts = connector.contacts
            .where((c) => c.type == advTypeChat || c.type == advTypeRepeater)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Trace Path'),
            centerTitle: true,
            actions: [
              BatteryIndicator(connector: connector),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              // Mode toggle
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _buildModeToggle(context),
              ),
              // Map mode or manual mode
              if (_mapMode) ...[
                Expanded(
                  child: _buildMapModeView(context, connector, repeaters),
                ),
              ] else ...[
                // Manual mode - select destination and path
                Expanded(
                  child: _buildManualModeView(context, connector, repeaters, allContacts),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeToggle(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: false,
          label: Text('Manual'),
          icon: Icon(Icons.list),
        ),
        ButtonSegment(
          value: true,
          label: Text('Map'),
          icon: Icon(Icons.map),
        ),
      ],
      selected: {_mapMode},
      onSelectionChanged: (selected) {
        setState(() {
          _mapMode = selected.first;
          if (_mapMode) {
            _lastTraceResult = null;
            _traceError = null;
          }
        });
      },
    );
  }

  Widget _buildManualModeView(
    BuildContext context,
    MeshCoreConnector connector,
    List<Contact> repeaters,
    List<Contact> allContacts,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Instructions
        Card(
          elevation: 0,
          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'How Trace Works',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Select repeaters to build a path. The trace packet will travel through each hop and return, measuring SNR at each point.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Path builder section
        Text(
          'Build Path',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),

        // Add repeater button
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: InkWell(
            onTap: () => _showAddRepeaterDialog(context, repeaters),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'Add node to path',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Current path display
        if (_selectedPath.isNotEmpty) ...[
          _buildCurrentPathDisplay(context),
          const SizedBox(height: 16),
        ],

        // Trace results
        if (_lastTraceResult != null) ...[
          _buildTraceResultCard(context),
          const SizedBox(height: 16),
        ],

        if (_traceError != null) ...[
          Card(
            color: colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _traceError!,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Action buttons
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _selectedPath.isEmpty
                    ? null
                    : () => setState(() {
                          _selectedPath.clear();
                          _lastTraceResult = null;
                          _traceError = null;
                        }),
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _selectedPath.isEmpty || _isTracing
                    ? null
                    : () => _startTrace(connector),
                icon: _isTracing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(_isTracing ? 'Tracing...' : 'Send Trace'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddRepeaterDialog(BuildContext context, List<Contact> repeaters) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Node to Path'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: repeaters.isEmpty
              ? Center(
                  child: Text(
                    'No repeaters found',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: repeaters.length,
                  itemBuilder: (context, index) {
                    final contact = repeaters[index];
                    final isAlreadySelected = _selectedPath.contains(contact);
                    final color = _getTypeColor(contact.type);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Icon(_getTypeIcon(contact.type), color: color, size: 20),
                      ),
                      title: Text(contact.name.isEmpty ? 'Unknown' : contact.name),
                      subtitle: Text(
                        'ID: ${contact.publicKeyHex.substring(0, 8)}...',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                      trailing: isAlreadySelected
                          ? Icon(Icons.check_circle, color: colorScheme.primary)
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          if (!isAlreadySelected) {
                            _selectedPath.add(contact);
                          }
                          _lastTraceResult = null;
                          _traceError = null;
                        });
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPathDisplay(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Current Path (${_selectedPath.length} hops)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Show path as: You → A → B → C → B → A → You
            Text(
              _buildPathDescription(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // Chips for each hop
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < _selectedPath.length; i++)
                  _buildPathChip(context, i),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildPathDescription() {
    if (_selectedPath.isEmpty) return 'No path selected';

    final names = _selectedPath.map((c) =>
        c.name.isEmpty ? c.publicKeyHex.substring(0, 4).toUpperCase() : c.name).toList();

    // Show path: You → A → B → C (response comes back automatically)
    return ['You', ...names].join(' → ');
  }

  Widget _buildPathChip(BuildContext context, int index) {
    final contact = _selectedPath[index];
    final theme = Theme.of(context);
    final hasSnr = _lastTraceResult != null && index < _lastTraceResult!.pathSnrs.length;
    final snr = hasSnr ? _lastTraceResult!.pathSnrs[index] : null;

    return Chip(
      avatar: CircleAvatar(
        backgroundColor: Colors.blue,
        radius: 12,
        child: Text(
          '${index + 1}',
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ),
      label: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            contact.name.isEmpty ? contact.publicKeyHex.substring(0, 4) : contact.name,
            style: theme.textTheme.bodySmall,
          ),
          if (snr != null)
            Text(
              '${snr.toStringAsFixed(1)} dB',
              style: TextStyle(
                fontSize: 10,
                color: _getSnrColor(snr),
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: () {
        setState(() {
          _selectedPath.removeAt(index);
          _lastTraceResult = null;
          _traceError = null;
        });
      },
    );
  }

  Widget _buildTraceResultCard(BuildContext context) {
    final result = _lastTraceResult!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Trace Results',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDetailRow(context, 'Total Hops', '${result.hopCount}'),
            if (result.pathSnrs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'SNR per Hop:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (int i = 0; i < result.pathSnrs.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getSnrColor(result.pathSnrs[i]).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: _getSnrColor(result.pathSnrs[i])),
                      ),
                      child: Text(
                        'Hop ${i + 1}: ${result.pathSnrs[i].toStringAsFixed(1)} dB',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _getSnrColor(result.pathSnrs[i]),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                context,
                'Average SNR',
                '${(result.pathSnrs.reduce((a, b) => a + b) / result.pathSnrs.length).toStringAsFixed(1)} dB',
              ),
              _buildDetailRow(
                context,
                'Min SNR',
                '${result.pathSnrs.reduce(min).toStringAsFixed(1)} dB',
              ),
              _buildDetailRow(
                context,
                'Max SNR',
                '${result.pathSnrs.reduce(max).toStringAsFixed(1)} dB',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMapModeView(BuildContext context, MeshCoreConnector connector, List<Contact> repeaters) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tileCache = context.read<MapTileCacheService>();

    // Get repeaters with locations
    final locatedRepeaters = repeaters
        .where((c) => c.hasLocation && c.latitude != 0 && c.longitude != 0)
        .toList();

    // Build markers
    final markers = <Marker>[];
    for (final repeater in locatedRepeaters) {
      final isSelected = _selectedPath.contains(repeater);
      final pathIndex = _selectedPath.indexOf(repeater);

      String? snrLabel;
      if (_lastTraceResult != null && isSelected && pathIndex < _lastTraceResult!.pathSnrs.length) {
        snrLabel = '${_lastTraceResult!.pathSnrs[pathIndex].toStringAsFixed(1)}dB';
      }

      markers.add(
        Marker(
          point: LatLng(repeater.latitude!, repeater.longitude!),
          width: 60,
          height: 60,
          child: GestureDetector(
            onTap: () => _toggleRepeaterInPath(repeater),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isSelected
                      ? Center(
                          child: Text(
                            '${pathIndex + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : const Icon(Icons.router, color: Colors.white, size: 20),
                ),
                if (snrLabel != null)
                  Positioned(
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getSnrColor(_lastTraceResult!.pathSnrs[pathIndex]),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        snrLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Build polyline for path
    final pathPoints = _selectedPath
        .where((c) => c.hasLocation)
        .map((c) => LatLng(c.latitude!, c.longitude!))
        .toList();

    final polylines = pathPoints.length > 1
        ? [
            Polyline(
              points: pathPoints,
              strokeWidth: 4,
              color: Colors.blueAccent,
            ),
          ]
        : <Polyline>[];

    // Calculate center
    LatLng initialCenter = const LatLng(39.8283, -98.5795);
    if (locatedRepeaters.isNotEmpty) {
      double latSum = 0, lonSum = 0;
      for (final r in locatedRepeaters) {
        latSum += r.latitude!;
        lonSum += r.longitude!;
      }
      initialCenter = LatLng(latSum / locatedRepeaters.length, lonSum / locatedRepeaters.length);
    }

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 10,
          ),
          children: [
            TileLayer(
              urlTemplate: kMapTileUrlTemplate,
              tileProvider: tileCache.tileProvider,
              userAgentPackageName: MapTileCacheService.userAgentPackageName,
              maxZoom: 19,
            ),
            if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
          ],
        ),
        // Info overlay
        Positioned(
          left: 16,
          top: 16,
          right: 16,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Tap repeaters to build path',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_selectedPath.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _buildPathDescription(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_lastTraceResult != null && _lastTraceResult!.pathSnrs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Avg SNR: ${(_lastTraceResult!.pathSnrs.reduce((a, b) => a + b) / _lastTraceResult!.pathSnrs.length).toStringAsFixed(1)} dB',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                  if (_traceError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _traceError!,
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Action buttons
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _selectedPath.isEmpty
                      ? null
                      : () => setState(() {
                            _selectedPath.clear();
                            _lastTraceResult = null;
                            _traceError = null;
                          }),
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _selectedPath.isEmpty || _isTracing
                      ? null
                      : () => _startTrace(connector),
                  icon: _isTracing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_isTracing ? 'Tracing...' : 'Send Trace'),
                ),
              ),
            ],
          ),
        ),
        // Legend
        Positioned(
          right: 16,
          bottom: 80,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLegendItem(Colors.green, 'Repeater'),
                  const SizedBox(height: 4),
                  _buildLegendItem(Colors.blue, 'Selected'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  void _toggleRepeaterInPath(Contact repeater) {
    setState(() {
      if (_selectedPath.contains(repeater)) {
        _selectedPath.remove(repeater);
      } else {
        _selectedPath.add(repeater);
      }
      _lastTraceResult = null;
      _traceError = null;
    });
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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

  Color _getSnrColor(double snr) {
    if (snr >= 10) return Colors.green;
    if (snr >= 5) return Colors.lightGreen;
    if (snr >= 0) return Colors.orange;
    if (snr >= -5) return Colors.deepOrange;
    return Colors.red;
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
}
