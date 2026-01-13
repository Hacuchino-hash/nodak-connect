import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../models/wardrive_sample.dart';
import '../services/wardrive_service.dart';

/// Screen for wardrive GPS coverage mapping
class WardriveScreen extends StatefulWidget {
  const WardriveScreen({super.key});

  @override
  State<WardriveScreen> createState() => _WardriveScreenState();
}

class _WardriveScreenState extends State<WardriveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _durationTimer;
  Timer? _mapRefreshTimer;
  bool _autoMode = false;
  final MapController _mapController = MapController();
  bool _followLocation = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _initService();
  }

  void _onTabChanged() {
    if (_tabController.index == 1) {
      // On map tab - start auto-refresh every 60 seconds
      _startMapRefresh();
    } else {
      _stopMapRefresh();
    }
  }

  void _startMapRefresh() {
    _stopMapRefresh();
    final service = context.read<WardriveService>();
    // Refresh immediately when switching to map (force refresh)
    service.fetchGlobalCoverage(force: true);
    // Then refresh every 30 seconds for more responsive updates
    _mapRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => service.fetchGlobalCoverage(force: true),
    );
  }

  void _stopMapRefresh() {
    _mapRefreshTimer?.cancel();
    _mapRefreshTimer = null;
  }

  Future<void> _initService() async {
    final service = context.read<WardriveService>();
    final connector = context.read<MeshCoreConnector>();
    service.setConnector(connector);
    await service.loadSettings();
    // Fetch global coverage from API
    service.fetchGlobalCoverage();
    // Get initial location and center map
    await _centerMapOnUserLocation(service);
  }

  Future<void> _centerMapOnUserLocation(WardriveService service) async {
    try {
      // Request initial position from service
      await service.requestInitialPosition();
      final pos = service.currentPosition;
      if (pos != null && mounted) {
        // Give the map a moment to initialize before moving
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          _mapController.move(
            LatLng(pos.latitude, pos.longitude),
            15, // Zoom level for local view
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to center map on user location: $e');
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _durationTimer?.cancel();
    _mapRefreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Consumer<WardriveService>(
      builder: (context, service, child) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Wardrive'),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: () => _showSettings(context, service),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.list_alt), text: 'Stats'),
                Tab(icon: Icon(Icons.map), text: 'Map'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildStatsTab(context, service),
              _buildMapTab(context, service),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatsTab(BuildContext context, WardriveService service) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status card
          _buildStatusCard(context, service),
          const SizedBox(height: 16),

          // GPS info card
          _buildGpsCard(context, service),
          const SizedBox(height: 16),

          // Stats card
          _buildStatsCard(context, service),
          const SizedBox(height: 16),

          // Telemetry card (top repeaters, etc.)
          _buildTelemetryCard(context, service),
          const SizedBox(height: 16),

          // Controls
          _buildControls(context, service),

          // Error display
          if (service.lastError != null) ...[
            const SizedBox(height: 16),
            _buildErrorCard(context, service.lastError!),
          ],

          // Recent samples
          if (service.samples.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Recent Samples',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _buildSamplesList(context, service),
          ],
        ],
      ),
    );
  }

  Widget _buildMapTab(BuildContext context, WardriveService service) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pos = service.currentPosition;

    // Default to center of US if no position
    final center = pos != null
        ? LatLng(pos.latitude, pos.longitude)
        : const LatLng(39.8283, -98.5795);

    // Build coverage rectangles from all covered tiles (local + global)
    final coverageRects = <Polygon>[];

    // Global coverage tiles (from API) - shown in lighter orange
    for (final tileHash in service.globalCoveredTiles) {
      if (tileHash.isNotEmpty) {
        try {
          final bounds = service.getGeohashBounds(tileHash);
          coverageRects.add(
            Polygon(
              points: [
                LatLng(bounds[0], bounds[1]), // SW
                LatLng(bounds[0], bounds[3]), // SE
                LatLng(bounds[2], bounds[3]), // NE
                LatLng(bounds[2], bounds[1]), // NW
              ],
              color: const Color(0xFFFFAB77).withValues(alpha: 0.3),
              borderColor: const Color(0xFFFFAB77),
              borderStrokeWidth: 1,
            ),
          );
        } catch (_) {
          // Skip invalid geohashes
        }
      }
    }

    // Local session tiles - green if confirmed, orange if pending
    for (final tileHash in service.coveredTiles) {
      if (tileHash.isNotEmpty) {
        try {
          final bounds = service.getGeohashBounds(tileHash);
          final isConfirmed = service.confirmedTiles.contains(tileHash);
          final tileColor = isConfirmed ? Colors.green : Colors.orange;
          coverageRects.add(
            Polygon(
              points: [
                LatLng(bounds[0], bounds[1]), // SW
                LatLng(bounds[0], bounds[3]), // SE
                LatLng(bounds[2], bounds[3]), // NE
                LatLng(bounds[2], bounds[1]), // NW
              ],
              color: tileColor.withValues(alpha: 0.5),
              borderColor: tileColor,
              borderStrokeWidth: 2,
            ),
          );
        } catch (_) {
          // Skip invalid geohashes
        }
      }
    }

    // Build sample markers
    final sampleMarkers = <Marker>[];
    for (final sample in service.samples) {
      final markerColor = _getSampleMarkerColor(sample);
      sampleMarkers.add(
        Marker(
          point: LatLng(sample.latitude, sample.longitude),
          width: 20,
          height: 20,
          child: Container(
            decoration: BoxDecoration(
              color: markerColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      );
    }

    // Current location marker
    final currentLocationMarker = pos != null
        ? Marker(
            point: LatLng(pos.latitude, pos.longitude),
            width: 30,
            height: 30,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(
                Icons.my_location,
                color: Colors.white,
                size: 18,
              ),
            ),
          )
        : null;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15,
            onPositionChanged: (position, hasGesture) {
              if (hasGesture) {
                setState(() => _followLocation = false);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'org.nodakmesh.ndmc',
            ),
            // Coverage rectangles
            PolygonLayer(polygons: coverageRects),
            // Sample markers
            MarkerLayer(markers: sampleMarkers),
            // Current location
            if (currentLocationMarker != null)
              MarkerLayer(markers: [currentLocationMarker]),
          ],
        ),
        // Map controls overlay
        Positioned(
          right: 16,
          bottom: 100,
          child: Column(
            children: [
              // Follow location toggle
              FloatingActionButton.small(
                heroTag: 'follow',
                onPressed: () {
                  setState(() => _followLocation = !_followLocation);
                  if (_followLocation && pos != null) {
                    _mapController.move(
                      LatLng(pos.latitude, pos.longitude),
                      _mapController.camera.zoom,
                    );
                  }
                },
                backgroundColor:
                    _followLocation ? colorScheme.primary : colorScheme.surface,
                child: Icon(
                  Icons.my_location,
                  color: _followLocation
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              // Zoom in
              FloatingActionButton.small(
                heroTag: 'zoomIn',
                onPressed: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  );
                },
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              // Zoom out
              FloatingActionButton.small(
                heroTag: 'zoomOut',
                onPressed: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  );
                },
                child: const Icon(Icons.remove),
              ),
            ],
          ),
        ),
        // Stats overlay
        Positioned(
          left: 16,
          top: 16,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${service.sampleCount} samples',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${service.coveredTiles.length} tiles (session)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (service.globalCoveredTiles.isNotEmpty)
                    Text(
                      '${service.globalCoveredTiles.length} tiles (global)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (service.currentTileHash != null)
                    Text(
                      'Tile: ${service.currentTileHash}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 4),
                  if (service.lastCoverageSync != null)
                    Text(
                      'Synced: ${_formatSyncTime(service.lastCoverageSync!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: service.isLoadingCoverage
                        ? null
                        : () => service.fetchGlobalCoverage(force: true),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (service.isLoadingCoverage)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            Icons.refresh,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          service.isLoadingCoverage ? 'Syncing...' : 'Refresh',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Capture button overlay
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: _buildMapControls(context, service),
        ),
      ],
    );
  }

  String _formatSyncTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  Color _getSampleMarkerColor(WardriveSample sample) {
    // Determine status considering skipped as "not applicable"
    final meshOk = sample.meshStatus == SampleDeliveryStatus.success;
    final webOk = sample.webStatus == SampleDeliveryStatus.success;
    final meshSkip = sample.meshStatus == SampleDeliveryStatus.skipped;
    final webSkip = sample.webStatus == SampleDeliveryStatus.skipped;
    final meshPending = sample.meshStatus == SampleDeliveryStatus.pending;
    final webPending = sample.webStatus == SampleDeliveryStatus.pending;
    final meshFailed = sample.meshStatus == SampleDeliveryStatus.failed;
    final webFailed = sample.webStatus == SampleDeliveryStatus.failed;

    // If anything is still pending, show orange (in progress)
    if (meshPending || webPending) return Colors.orange;

    // Both skipped = grey (nothing configured)
    if (meshSkip && webSkip) return Colors.grey;

    // Check if all enabled deliveries succeeded
    // Success + Skip = Green (the one that was enabled succeeded)
    // Success + Success = Green (both succeeded)
    final meshGood = meshOk || meshSkip;
    final webGood = webOk || webSkip;

    if (meshGood && webGood) return Colors.green;

    // At least one failed
    if (meshFailed && webFailed) return Colors.red;

    // Partial failure (one succeeded/skipped, one failed)
    return Colors.orange;
  }

  Widget _buildMapControls(BuildContext context, WardriveService service) {
    if (service.isIdle) {
      return FilledButton.icon(
        onPressed: () => service.start(autoMode: _autoMode),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start Wardrive'),
      );
    } else if (service.isRunning) {
      return Row(
        children: [
          if (!_autoMode)
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => service.captureSample(),
                icon: const Icon(Icons.add_location),
                label: const Text('Capture'),
              ),
            ),
          if (!_autoMode) const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: service.stop,
              icon: const Icon(Icons.stop),
              label: const Text('Stop'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ],
      );
    } else {
      return FilledButton.icon(
        onPressed: () => service.resume(autoMode: _autoMode),
        icon: const Icon(Icons.play_arrow),
        label: const Text('Resume'),
      );
    }
  }

  Widget _buildStatusCard(BuildContext context, WardriveService service) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final statusColor = service.isRunning
        ? Colors.green
        : service.isPaused
            ? Colors.orange
            : colorScheme.onSurfaceVariant;

    final statusText = service.isRunning
        ? 'Running'
        : service.isPaused
            ? 'Paused'
            : 'Idle';

    final statusIcon = service.isRunning
        ? Icons.play_circle_filled
        : service.isPaused
            ? Icons.pause_circle_filled
            : Icons.stop_circle;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: statusColor.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                  if (service.sessionStartTime != null)
                    Text(
                      'Duration: ${service.sessionDuration}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (_autoMode && service.isRunning)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'AUTO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsCard(BuildContext context, WardriveService service) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pos = service.currentPosition;

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
                Icon(
                  Icons.gps_fixed,
                  color: pos != null ? Colors.green : colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'GPS Location',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (pos != null) ...[
              _buildGpsRow(context, 'Latitude', pos.latitude.toStringAsFixed(6)),
              _buildGpsRow(context, 'Longitude', pos.longitude.toStringAsFixed(6)),
              _buildGpsRow(context, 'Accuracy', '${pos.accuracy.toStringAsFixed(1)} m'),
              _buildGpsRow(context, 'Altitude', '${pos.altitude.toStringAsFixed(1)} m'),
            ] else
              Text(
                'Waiting for GPS fix...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsRow(BuildContext context, String label, String value) {
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
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(BuildContext context, WardriveService service) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final distanceKm = service.distanceTraveled / 1000;
    final distanceStr = distanceKm >= 1
        ? '${distanceKm.toStringAsFixed(2)} km'
        : '${service.distanceTraveled.toStringAsFixed(0)} m';

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
        child: Row(
          children: [
            Expanded(
              child: _buildStatItem(
                context,
                Icons.pin_drop,
                service.sampleCount.toString(),
                'Samples',
              ),
            ),
            Container(width: 1, height: 40, color: colorScheme.outlineVariant),
            Expanded(
              child: _buildStatItem(
                context,
                Icons.grid_on,
                service.coveredTiles.length.toString(),
                'Tiles',
              ),
            ),
            Container(width: 1, height: 40, color: colorScheme.outlineVariant),
            Expanded(
              child: _buildStatItem(
                context,
                Icons.straighten,
                distanceStr,
                'Distance',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryCard(BuildContext context, WardriveService service) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final telemetry = service.telemetryData;

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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Network Telemetry',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (service.isLoadingTelemetry)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => service.fetchTelemetry(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (telemetry == null || telemetry.isEmpty)
              Center(
                child: Text(
                  'Tap refresh to load network stats',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              )
            else ...[
              // Total coverage tiles
              if (telemetry['totalTiles'] != null)
                _buildTelemetryRow(
                  context,
                  Icons.grid_on,
                  'Total Coverage',
                  '${telemetry['totalTiles']} tiles',
                ),
              // Active nodes
              if (telemetry['activeNodes'] != null)
                _buildTelemetryRow(
                  context,
                  Icons.cell_tower,
                  'Active Nodes',
                  '${telemetry['activeNodes']}',
                ),
              // Top repeaters
              if (telemetry['topRepeaters'] != null &&
                  telemetry['topRepeaters'] is List &&
                  (telemetry['topRepeaters'] as List).isNotEmpty) ...[
                const Divider(height: 16),
                Text(
                  'Top Repeaters',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                ...(telemetry['topRepeaters'] as List)
                    .take(5)
                    .map<Widget>((repeater) {
                  final name = repeater['name'] ?? 'Unknown';
                  final samples = repeater['samples'] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cell_tower,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(name)),
                        Text(
                          '$samples samples',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(label),
          const Spacer(),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Icon(icon, color: colorScheme.primary, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildControls(BuildContext context, WardriveService service) {
    return Column(
      children: [
        // Mode selector
        Row(
          children: [
            Expanded(
              child: _buildModeButton(
                context,
                'Manual',
                !_autoMode,
                () => setState(() => _autoMode = false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildModeButton(
                context,
                service.pingMode == WardrivePingMode.fill
                    ? 'Auto (Fill)'
                    : 'Auto (${service.autoIntervalSeconds}s)',
                _autoMode,
                () => setState(() => _autoMode = true),
              ),
            ),
          ],
        ),
        // Show skip reason if any
        if (service.lastSkipReason != null && _autoMode) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service.lastSkipReason!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.amber.shade700,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),

        // Action buttons
        if (service.isIdle) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => service.start(autoMode: _autoMode),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Wardrive'),
            ),
          ),
        ] else if (service.isRunning) ...[
          if (!_autoMode) ...[
            // Manual mode: Capture button on its own row
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => service.captureSample(),
                icon: const Icon(Icons.add_location),
                label: const Text('Capture Sample'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Pause and Stop buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: service.pause,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: service.stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
        ] else if (service.isPaused) ...[
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => service.resume(autoMode: _autoMode),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: service.stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
        ],

        // Reset button
        if (!service.isIdle && service.sampleCount > 0) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _confirmReset(context, service),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset Session'),
          ),
        ],
      ],
    );
  }

  Widget _buildModeButton(
    BuildContext context,
    String label,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String error) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: Colors.red.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSamplesList(BuildContext context, WardriveService service) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final recentSamples = service.samples.reversed.take(10).toList();

    return Column(
      children: [
        for (final sample in recentSamples)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sample.coordinatesDisplay,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              sample.timeDisplay,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: sample.isManual
                                    ? Colors.blue.withValues(alpha: 0.1)
                                    : Colors.purple.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                sample.isManual ? 'M' : 'A',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color:
                                      sample.isManual ? Colors.blue : Colors.purple,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Status icons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStatusIcon(sample.meshStatus, 'Mesh'),
                      const SizedBox(width: 4),
                      _buildStatusIcon(sample.webStatus, 'Web'),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusIcon(SampleDeliveryStatus status, String label) {
    IconData icon;
    Color color;

    switch (status) {
      case SampleDeliveryStatus.pending:
        icon = Icons.schedule;
        color = Colors.orange;
        break;
      case SampleDeliveryStatus.success:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case SampleDeliveryStatus.failed:
        icon = Icons.cancel;
        color = Colors.red;
        break;
      case SampleDeliveryStatus.skipped:
        icon = Icons.remove_circle_outline;
        color = Colors.grey;
        break;
    }

    return Tooltip(
      message: '$label: ${status.name}',
      child: Icon(icon, size: 18, color: color),
    );
  }

  void _confirmReset(BuildContext context, WardriveService service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Session?'),
        content: const Text(
          'This will clear all samples and reset the session. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              service.reset();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context, WardriveService service) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _WardriveSettingsSheet(service: service),
    );
  }
}

class _WardriveSettingsSheet extends StatefulWidget {
  final WardriveService service;

  const _WardriveSettingsSheet({required this.service});

  @override
  State<_WardriveSettingsSheet> createState() => _WardriveSettingsSheetState();
}

class _WardriveSettingsSheetState extends State<_WardriveSettingsSheet> {
  late TextEditingController _channelController;
  late TextEditingController _apiController;
  late int _selectedInterval;
  late double _selectedMinDistance;
  late WardrivePingMode _selectedPingMode;

  @override
  void initState() {
    super.initState();
    _channelController = TextEditingController(text: widget.service.channelName);
    _apiController = TextEditingController(text: widget.service.apiEndpoint);
    _selectedInterval = widget.service.autoIntervalSeconds;
    _selectedMinDistance = widget.service.minDistanceMeters;
    _selectedPingMode = widget.service.pingMode;
  }

  @override
  void dispose() {
    _channelController.dispose();
    _apiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wardrive Settings',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),

            // Send options
            SwitchListTile(
              title: const Text('Send to Channel'),
              subtitle: const Text('Post samples to mesh channel'),
              value: widget.service.sendToChannel,
              onChanged: (value) {
                widget.service.setSendToChannel(value);
                setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text('Send to API'),
              subtitle: const Text('Submit samples to coverage API'),
              value: widget.service.sendToApi,
              onChanged: (value) {
                widget.service.setSendToApi(value);
                setState(() {});
              },
            ),

            const Divider(),

            // Ping mode
            Text('Auto Ping Mode', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<WardrivePingMode>(
              segments: const [
                ButtonSegment(
                  value: WardrivePingMode.fill,
                  label: Text('Fill'),
                  icon: Icon(Icons.grid_on),
                ),
                ButtonSegment(
                  value: WardrivePingMode.interval,
                  label: Text('Interval'),
                  icon: Icon(Icons.timer),
                ),
              ],
              selected: {_selectedPingMode},
              onSelectionChanged: (selected) {
                setState(() => _selectedPingMode = selected.first);
                widget.service.setPingMode(selected.first);
              },
            ),
            const SizedBox(height: 4),
            Text(
              _selectedPingMode == WardrivePingMode.fill
                  ? 'Automatically ping when entering new uncovered tiles'
                  : 'Ping at fixed intervals with minimum distance check',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 16),

            // Interval settings (only shown in interval mode)
            if (_selectedPingMode == WardrivePingMode.interval) ...[
              Text('Time Interval', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [15, 30, 60, 120].map((seconds) {
                  final isSelected = _selectedInterval == seconds;
                  return ChoiceChip(
                    label: Text('${seconds}s'),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedInterval = seconds);
                        widget.service.setAutoInterval(seconds);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text('Minimum Distance', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [25.0, 50.0, 100.0, 200.0].map((meters) {
                  final isSelected = _selectedMinDistance == meters;
                  return ChoiceChip(
                    label: Text('${meters.toInt()}m'),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedMinDistance = meters);
                        widget.service.setMinDistance(meters);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],

            const Divider(),

            // Channel name
            TextField(
              controller: _channelController,
              decoration: const InputDecoration(
                labelText: 'Channel Name',
                hintText: '#wardrive',
                prefixIcon: Icon(Icons.tag),
              ),
              onChanged: (value) => widget.service.setChannelName(value),
            ),
            const SizedBox(height: 16),

            // API endpoint
            TextField(
              controller: _apiController,
              decoration: const InputDecoration(
                labelText: 'API Endpoint',
                hintText: 'https://coverage.ndme.sh/put-sample',
                prefixIcon: Icon(Icons.cloud),
              ),
              onChanged: (value) => widget.service.setApiEndpoint(value),
            ),

            const SizedBox(height: 16),
            const Divider(),

            // Ignored repeaters section
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Ignored Repeaters'),
              subtitle: Text(
                widget.service.ignoredRepeaterIds.isEmpty
                    ? 'None - all repeaters counted for coverage'
                    : '${widget.service.ignoredRepeaterIds.length} repeater(s) ignored',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showIgnoredRepeatersDialog(context),
            ),
            const SizedBox(height: 4),
            Text(
              'Mobile repeaters can skew coverage data. Ignore them so their coverage isn\'t counted.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showIgnoredRepeatersDialog(BuildContext context) {
    final connector = context.read<MeshCoreConnector>();
    final repeaters = connector.contacts
        .where((c) => c.type == advTypeRepeater)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final ignoredIds = widget.service.ignoredRepeaterIds;

          return AlertDialog(
            title: const Text('Ignored Repeaters'),
            content: SizedBox(
              width: double.maxFinite,
              child: repeaters.isEmpty
                  ? const Center(child: Text('No repeaters found'))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: repeaters.length,
                      itemBuilder: (context, index) {
                        final repeater = repeaters[index];
                        final isIgnored = ignoredIds.contains(repeater.publicKeyHex);

                        return CheckboxListTile(
                          title: Text(repeater.name),
                          subtitle: Text(isIgnored ? 'Ignored for coverage' : 'Counted for coverage'),
                          value: isIgnored,
                          secondary: CircleAvatar(
                            backgroundColor: isIgnored ? Colors.red.shade100 : Colors.orange.shade100,
                            child: Icon(
                              Icons.cell_tower,
                              color: isIgnored ? Colors.red : Colors.orange,
                            ),
                          ),
                          onChanged: (value) async {
                            if (value == true) {
                              await widget.service.addIgnoredRepeater(repeater.publicKeyHex);
                            } else {
                              await widget.service.removeIgnoredRepeater(repeater.publicKeyHex);
                            }
                            setDialogState(() {});
                            setState(() {}); // Update parent
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }
}
