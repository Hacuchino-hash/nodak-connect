import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/contact.dart';
import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../services/repeater_command_service.dart';
import '../services/map_tile_cache_service.dart';

/// Represents a one-hop neighbor of a repeater
class NeighborInfo {
  final String name;
  final String pubkeyPrefix;
  final int? rssiIn; // Signal from neighbor to us
  final int? rssiOut; // Signal from us to neighbor
  final double? snrIn;
  final double? snrOut;
  final int? lastSeenSecs;
  final double? latitude;
  final double? longitude;

  NeighborInfo({
    required this.name,
    required this.pubkeyPrefix,
    this.rssiIn,
    this.rssiOut,
    this.snrIn,
    this.snrOut,
    this.lastSeenSecs,
    this.latitude,
    this.longitude,
  });

  bool get hasLocation => latitude != null && longitude != null;

  String get rssiInStr => rssiIn != null ? '${rssiIn}dBm' : '--';
  String get rssiOutStr => rssiOut != null ? '${rssiOut}dBm' : '--';
  String get snrInStr => snrIn != null ? '${snrIn!.toStringAsFixed(1)}dB' : '--';
  String get snrOutStr => snrOut != null ? '${snrOut!.toStringAsFixed(1)}dB' : '--';

  String get lastSeenStr {
    if (lastSeenSecs == null) return '--';
    if (lastSeenSecs! < 60) return '${lastSeenSecs}s ago';
    if (lastSeenSecs! < 3600) return '${lastSeenSecs! ~/ 60}m ago';
    return '${lastSeenSecs! ~/ 3600}h ago';
  }
}

class RepeaterNeighborsScreen extends StatefulWidget {
  final Contact repeater;
  final String password;

  const RepeaterNeighborsScreen({
    super.key,
    required this.repeater,
    required this.password,
  });

  @override
  State<RepeaterNeighborsScreen> createState() => _RepeaterNeighborsScreenState();
}

class _RepeaterNeighborsScreenState extends State<RepeaterNeighborsScreen> {
  bool _isLoading = true;
  String? _error;
  List<NeighborInfo> _neighbors = [];
  StreamSubscription<Uint8List>? _frameSubscription;
  RepeaterCommandService? _commandService;
  bool _showMap = false;
  final MapTileCacheService _mapTileService = MapTileCacheService();

  @override
  void initState() {
    super.initState();
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    _commandService = RepeaterCommandService(connector);
    _setupMessageListener();
    _loadNeighbors();
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    _commandService?.dispose();
    super.dispose();
  }

  void _setupMessageListener() {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    _frameSubscription = connector.receivedFrames.listen((frame) {
      if (frame.isEmpty) return;
      if (frame[0] == respCodeContactMsgRecv ||
          frame[0] == respCodeContactMsgRecvV3) {
        _handleTextMessageResponse(frame);
      }
    });
  }

  void _handleTextMessageResponse(Uint8List frame) {
    final parsed = parseContactMessageText(frame);
    if (parsed == null) return;
    final repeaterPrefix = widget.repeater.publicKey.sublist(0, 6);
    if (!_matchesPrefix(parsed.senderPrefix, repeaterPrefix)) return;
    _commandService?.handleResponse(widget.repeater, parsed.text);
  }

  bool _matchesPrefix(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _loadNeighbors() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _commandService!.sendCommand(
        widget.repeater,
        'neighbors',
        retries: 3,
      );
      _parseNeighborsResponse(response);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _parseNeighborsResponse(String response) {
    final connector = context.read<MeshCoreConnector>();
    final lines = response.split('\n');
    final neighbors = <NeighborInfo>[];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      // Parse neighbor line - format varies by firmware
      // Common format: "name: NodeName, rssi: -70, snr: 8.5, ..."
      // Or: "NodeName -70dBm 8.5dB"
      final neighbor = _parseNeighborLine(line.trim(), connector);
      if (neighbor != null) {
        neighbors.add(neighbor);
      }
    }

    setState(() {
      _neighbors = neighbors;
      _isLoading = false;
    });
  }

  NeighborInfo? _parseNeighborLine(String line, MeshCoreConnector connector) {
    String name = '';
    String pubkeyPrefix = '';
    int? rssiIn;
    int? rssiOut;
    double? snrIn;
    double? snrOut;
    int? lastSeenSecs;
    double? latitude;
    double? longitude;
    Contact? matchedContact;

    // Extract pubkey prefix - look for 6-8 char hex strings
    final pubkeyMatch = RegExp(r'\b([0-9a-fA-F]{6,8})\b').firstMatch(line);
    if (pubkeyMatch != null) {
      pubkeyPrefix = pubkeyMatch.group(1)!.toUpperCase();

      // Look up contact by pubkey prefix to get actual name and location
      matchedContact = connector.contacts.where(
        (c) => c.publicKeyHex.toUpperCase().startsWith(pubkeyPrefix.substring(0, 6)),
      ).firstOrNull;
    }

    // Try to extract name from line (pattern: "name: X")
    final nameMatch = RegExp(r'name:\s*([^,\n]+)', caseSensitive: false).firstMatch(line);
    if (nameMatch != null) {
      name = nameMatch.group(1)!.trim();
    }

    // If we found a matching contact, use its name and location
    if (matchedContact != null) {
      name = matchedContact.name;
      if (matchedContact.hasLocation) {
        latitude = matchedContact.latitude;
        longitude = matchedContact.longitude;
      }
    } else if (name.isEmpty && pubkeyPrefix.isNotEmpty) {
      // Fall back to pubkey prefix as display name
      name = pubkeyPrefix;
    }

    // Extract RSSI values (look for numbers followed by dBm or just negative numbers)
    final rssiMatches = RegExp(r'(-?\d+)\s*(?:dBm)?', caseSensitive: false).allMatches(line);
    final rssiList = rssiMatches
        .map((m) => int.tryParse(m.group(1)!))
        .where((v) => v != null && v < 0) // RSSI values are negative
        .cast<int>()
        .toList();
    if (rssiList.isNotEmpty) {
      rssiIn = rssiList[0];
      if (rssiList.length > 1) {
        rssiOut = rssiList[1];
      }
    }

    // Extract SNR values (positive decimals, typically 0-15 range)
    final snrMatches = RegExp(r'\b(\d+\.?\d*)\s*(?:dB(?!m)|snr)', caseSensitive: false).allMatches(line);
    final snrList = snrMatches
        .map((m) => double.tryParse(m.group(1)!))
        .where((v) => v != null && v >= 0 && v < 20) // SNR typically 0-15
        .cast<double>()
        .toList();
    if (snrList.isNotEmpty) {
      snrIn = snrList[0];
      if (snrList.length > 1) {
        snrOut = snrList[1];
      }
    }

    // Extract last seen if present
    final lastSeenMatch = RegExp(r'(\d+)\s*(s|sec|m|min|h|hr|hour)', caseSensitive: false).firstMatch(line);
    if (lastSeenMatch != null) {
      final value = int.parse(lastSeenMatch.group(1)!);
      final unit = lastSeenMatch.group(2)!.toLowerCase();
      if (unit.startsWith('h')) {
        lastSeenSecs = value * 3600;
      } else if (unit.startsWith('m')) {
        lastSeenSecs = value * 60;
      } else {
        lastSeenSecs = value;
      }
    }

    // Need at least a pubkey or name to be valid
    if (name.isEmpty && pubkeyPrefix.isEmpty) return null;
    if (name.isEmpty) name = 'Unknown';

    return NeighborInfo(
      name: name,
      pubkeyPrefix: pubkeyPrefix,
      rssiIn: rssiIn,
      rssiOut: rssiOut,
      snrIn: snrIn,
      snrOut: snrOut,
      lastSeenSecs: lastSeenSecs,
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('One-Hop Neighbors'),
            Text(
              widget.repeater.name,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          if (_neighbors.any((n) => n.hasLocation) || widget.repeater.hasLocation)
            IconButton(
              icon: Icon(_showMap ? Icons.list : Icons.map),
              tooltip: _showMap ? 'Show List' : 'Show Map',
              onPressed: () => setState(() => _showMap = !_showMap),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadNeighbors,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading neighbors...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Failed to load neighbors', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadNeighbors,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_neighbors.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('No neighbors found'),
          ],
        ),
      );
    }

    return _showMap ? _buildMapView() : _buildListView();
  }

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _neighbors.length,
      itemBuilder: (context, index) {
        final neighbor = _neighbors[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.green.withValues(alpha: 0.2),
                      child: const Icon(Icons.cell_tower, color: Colors.green),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            neighbor.name,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          if (neighbor.pubkeyPrefix.isNotEmpty)
                            Text(
                              neighbor.pubkeyPrefix,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                        ],
                      ),
                    ),
                    if (neighbor.lastSeenSecs != null)
                      Chip(
                        label: Text(neighbor.lastSeenStr, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
                const Divider(height: 16),
                // Signal strength indicators
                Row(
                  children: [
                    Expanded(
                      child: _buildSignalColumn(
                        'Inbound',
                        Icons.arrow_downward,
                        neighbor.rssiInStr,
                        neighbor.snrInStr,
                        Colors.blue,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.grey[300],
                    ),
                    Expanded(
                      child: _buildSignalColumn(
                        'Outbound',
                        Icons.arrow_upward,
                        neighbor.rssiOutStr,
                        neighbor.snrOutStr,
                        Colors.orange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSignalColumn(
    String label,
    IconData icon,
    String rssi,
    String snr,
    Color color,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 4),
        Text(rssi, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(snr, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildMapView() {
    // Get repeater's location as center
    LatLng center;
    if (widget.repeater.hasLocation) {
      center = LatLng(widget.repeater.latitude!, widget.repeater.longitude!);
    } else {
      // Use first neighbor with location
      final withLocation = _neighbors.firstWhere(
        (n) => n.hasLocation,
        orElse: () => _neighbors.first,
      );
      if (withLocation.hasLocation) {
        center = LatLng(withLocation.latitude!, withLocation.longitude!);
      } else {
        return const Center(child: Text('No location data available for map'));
      }
    }

    final markers = <Marker>[];
    final lines = <Polyline>[];
    final colorScheme = Theme.of(context).colorScheme;

    // Add repeater marker
    if (widget.repeater.hasLocation) {
      markers.add(Marker(
        point: center,
        width: 40,
        height: 40,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.orange,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(Icons.cell_tower, color: Colors.white, size: 24),
        ),
      ));
    }

    // Add neighbor markers and connection lines
    for (final neighbor in _neighbors) {
      if (!neighbor.hasLocation) continue;

      final neighborPoint = LatLng(neighbor.latitude!, neighbor.longitude!);

      markers.add(Marker(
        point: neighborPoint,
        width: 36,
        height: 36,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(Icons.cell_tower, color: Colors.white, size: 20),
        ),
      ));

      // Add connection line with signal info
      if (widget.repeater.hasLocation) {
        lines.add(Polyline(
          points: [center, neighborPoint],
          color: colorScheme.primary.withValues(alpha: 0.7),
          strokeWidth: 3,
        ));
      }
    }

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 12,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'org.nodakmesh.ndmc',
          tileProvider: _mapTileService.tileProvider,
          additionalOptions: _mapTileService.defaultHeaders,
        ),
        PolylineLayer(polylines: lines),
        MarkerLayer(markers: markers),
      ],
    );
  }
}
