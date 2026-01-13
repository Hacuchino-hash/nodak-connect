import 'dart:async';
import 'dart:convert';

import 'package:dart_geohash/dart_geohash.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../connector/meshcore_connector.dart';
import '../models/channel.dart';
import '../models/wardrive_sample.dart';
import '../storage/wardrive_settings_store.dart';

enum WardriveState {
  idle,
  running,
  paused,
}

enum WardrivePingMode {
  /// Only ping when entering a new uncovered tile
  fill,
  /// Ping at time intervals with minimum distance check
  interval,
}

class WardriveService extends ChangeNotifier {
  final WardriveSettingsStore _settingsStore = WardriveSettingsStore();
  final GeoHasher _geoHasher = GeoHasher();

  WardriveState _state = WardriveState.idle;
  Position? _currentPosition;
  Position? _startPosition;
  Position? _lastSamplePosition;
  double _distanceTraveled = 0;
  int _sampleCount = 0;
  final List<WardriveSample> _samples = [];
  final Set<String> _coveredTiles = {}; // Local session tiles (attempted)
  final Set<String> _confirmedTiles = {}; // Tiles with successful delivery
  final Set<String> _globalCoveredTiles = {}; // Tiles from API
  bool _isLoadingCoverage = false;
  Map<String, dynamic>? _telemetryData;
  bool _isLoadingTelemetry = false;
  DateTime? _lastCoverageSync;
  Timer? _autoSampleTimer;
  Timer? _fillModeTimer;
  int _autoIntervalSeconds = 30;
  double _minDistanceMeters = 50; // Minimum distance for interval mode
  WardrivePingMode _pingMode = WardrivePingMode.fill;
  bool _sendToChannel = true;
  bool _sendToApi = true;
  String _channelName = WardriveSettingsStore.defaultChannelName;
  String _apiEndpoint = WardriveSettingsStore.defaultApiEndpoint;
  DateTime? _sessionStartTime;
  String? _lastError;
  String? _lastSkipReason;

  MeshCoreConnector? _connector;
  List<String> _ignoredRepeaterIds = [];

  /// Coverage tile precision (6 = ~1.2km x 0.6km, same as web app)
  static const int coveragePrecision = 6;
  /// Sample precision (8 = finer ~38m x 19m)
  static const int samplePrecision = 8;

  // Getters
  WardriveState get state => _state;
  bool get isRunning => _state == WardriveState.running;
  bool get isPaused => _state == WardriveState.paused;
  bool get isIdle => _state == WardriveState.idle;
  Position? get currentPosition => _currentPosition;
  double get distanceTraveled => _distanceTraveled;
  int get sampleCount => _sampleCount;
  List<WardriveSample> get samples => List.unmodifiable(_samples);
  Set<String> get coveredTiles => Set.unmodifiable(_coveredTiles);
  Set<String> get confirmedTiles => Set.unmodifiable(_confirmedTiles);
  Set<String> get globalCoveredTiles => Set.unmodifiable(_globalCoveredTiles);
  Set<String> get allCoveredTiles => {..._coveredTiles, ..._globalCoveredTiles};
  bool get isLoadingCoverage => _isLoadingCoverage;
  bool get isLoadingTelemetry => _isLoadingTelemetry;
  Map<String, dynamic>? get telemetryData => _telemetryData;
  DateTime? get lastCoverageSync => _lastCoverageSync;
  int get autoIntervalSeconds => _autoIntervalSeconds;
  double get minDistanceMeters => _minDistanceMeters;
  WardrivePingMode get pingMode => _pingMode;
  bool get sendToChannel => _sendToChannel;
  bool get sendToApi => _sendToApi;
  String get channelName => _channelName;
  String get apiEndpoint => _apiEndpoint;
  DateTime? get sessionStartTime => _sessionStartTime;
  String? get lastError => _lastError;
  String? get lastSkipReason => _lastSkipReason;
  GeoHasher get geoHasher => _geoHasher;
  List<String> get ignoredRepeaterIds => List.unmodifiable(_ignoredRepeaterIds);

  String get sessionDuration {
    if (_sessionStartTime == null) return '00:00';
    final diff = DateTime.now().difference(_sessionStartTime!);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final seconds = diff.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Calculate coverage tile geohash (6-char precision, same as web app)
  String getCoverageTileHash(double lat, double lon) {
    final fullHash = _geoHasher.encode(lon, lat, precision: samplePrecision);
    return fullHash.substring(0, coveragePrecision);
  }

  /// Calculate sample geohash (8-char precision for finer location)
  String getSampleHash(double lat, double lon) {
    return _geoHasher.encode(lon, lat, precision: samplePrecision);
  }

  /// Get the bounding box for a geohash tile
  /// Returns [swLat, swLon, neLat, neLon]
  List<double> getGeohashBounds(String geohash) {
    final decoded = _geoHasher.decode(geohash);
    // decoded gives center point with error margins
    final lat = decoded[1];
    final lon = decoded[0];
    // Calculate approximate bounds based on precision
    // Each character adds ~5 bits, halving the range
    final latErr = 90.0 / (1 << (geohash.length * 5 ~/ 2));
    final lonErr = 180.0 / (1 << ((geohash.length * 5 + 1) ~/ 2));
    return [
      lat - latErr, // SW lat
      lon - lonErr, // SW lon
      lat + latErr, // NE lat
      lon + lonErr, // NE lon
    ];
  }

  /// Check if a tile is already covered (local or global)
  bool isTileCovered(double lat, double lon) {
    final hash = getCoverageTileHash(lat, lon);
    return _coveredTiles.contains(hash) || _globalCoveredTiles.contains(hash);
  }

  /// Get current tile hash for display
  String? get currentTileHash {
    if (_currentPosition == null) return null;
    return getCoverageTileHash(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );
  }

  void setConnector(MeshCoreConnector connector) {
    _connector = connector;
  }

  Future<void> loadSettings() async {
    _channelName = await _settingsStore.getChannelName();
    _apiEndpoint = await _settingsStore.getApiEndpoint();
    _autoIntervalSeconds = await _settingsStore.getAutoInterval();
    _sendToChannel = await _settingsStore.getSendToChannel();
    _sendToApi = await _settingsStore.getSendToApi();
    _ignoredRepeaterIds = await _settingsStore.getIgnoredRepeaterIds();
    notifyListeners();
  }

  /// Fetch existing coverage tiles from the API
  Future<void> fetchGlobalCoverage({bool force = false}) async {
    if (_isLoadingCoverage && !force) return;

    _isLoadingCoverage = true;
    notifyListeners();

    try {
      // Get base URL from api endpoint (remove /put-sample)
      final baseUrl = _apiEndpoint.replaceAll('/put-sample', '');
      final url = '$baseUrl/get-wardrive-coverage';
      debugPrint('Fetching coverage from: $url');

      final response = await http.get(
        Uri.parse(url),
      ).timeout(const Duration(seconds: 30));

      debugPrint('Coverage response: ${response.statusCode}, body length: ${response.body.length}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> tiles = decoded is List ? decoded : [];
        final previousCount = _globalCoveredTiles.length;
        _globalCoveredTiles.clear();
        for (final tile in tiles) {
          if (tile is String && tile.isNotEmpty) {
            _globalCoveredTiles.add(tile);
          }
        }
        _lastCoverageSync = DateTime.now();
        _lastError = null;
        debugPrint('Coverage loaded: ${_globalCoveredTiles.length} tiles (was $previousCount)');
      } else {
        _lastError = 'Failed to fetch coverage: HTTP ${response.statusCode}';
        debugPrint('Coverage fetch failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _lastError = 'Failed to fetch coverage: $e';
      debugPrint('Coverage fetch error: $e');
    }

    _isLoadingCoverage = false;
    notifyListeners();
  }

  /// Fetch telemetry data (top repeaters, stats, etc.) from the API
  Future<void> fetchTelemetry() async {
    if (_isLoadingTelemetry) return;

    _isLoadingTelemetry = true;
    notifyListeners();

    try {
      final baseUrl = _apiEndpoint.replaceAll('/put-sample', '');
      final response = await http.get(
        Uri.parse('$baseUrl/get-wardrive-telemetry'),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _telemetryData = jsonDecode(response.body) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('Failed to fetch telemetry: $e');
    }

    _isLoadingTelemetry = false;
    notifyListeners();
  }

  /// Refresh both coverage and telemetry data
  Future<void> refreshData() async {
    await Future.wait([
      fetchGlobalCoverage(),
      fetchTelemetry(),
    ]);
  }

  Future<void> setAutoInterval(int seconds) async {
    _autoIntervalSeconds = seconds;
    await _settingsStore.setAutoInterval(seconds);
    notifyListeners();
  }

  void setMinDistance(double meters) {
    _minDistanceMeters = meters;
    notifyListeners();
  }

  void setPingMode(WardrivePingMode mode) {
    _pingMode = mode;
    notifyListeners();
  }

  Future<void> setSendToChannel(bool value) async {
    _sendToChannel = value;
    await _settingsStore.setSendToChannel(value);
    notifyListeners();
  }

  Future<void> setSendToApi(bool value) async {
    _sendToApi = value;
    await _settingsStore.setSendToApi(value);
    notifyListeners();
  }

  Future<void> setChannelName(String name) async {
    _channelName = name;
    await _settingsStore.setChannelName(name);
    notifyListeners();
  }

  Future<void> setApiEndpoint(String endpoint) async {
    _apiEndpoint = endpoint;
    await _settingsStore.setApiEndpoint(endpoint);
    notifyListeners();
  }

  Future<void> setIgnoredRepeaterIds(List<String> ids) async {
    _ignoredRepeaterIds = List.from(ids);
    await _settingsStore.setIgnoredRepeaterIds(ids);
    notifyListeners();
  }

  Future<void> addIgnoredRepeater(String pubKeyHex) async {
    if (!_ignoredRepeaterIds.contains(pubKeyHex)) {
      _ignoredRepeaterIds = [..._ignoredRepeaterIds, pubKeyHex];
      await _settingsStore.setIgnoredRepeaterIds(_ignoredRepeaterIds);
      notifyListeners();
    }
  }

  Future<void> removeIgnoredRepeater(String pubKeyHex) async {
    if (_ignoredRepeaterIds.contains(pubKeyHex)) {
      _ignoredRepeaterIds = _ignoredRepeaterIds.where((id) => id != pubKeyHex).toList();
      await _settingsStore.setIgnoredRepeaterIds(_ignoredRepeaterIds);
      notifyListeners();
    }
  }

  bool isRepeaterIgnored(String pubKeyHex) {
    return _ignoredRepeaterIds.contains(pubKeyHex);
  }

  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _lastError = 'Location services are disabled';
      notifyListeners();
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _lastError = 'Location permission denied';
        notifyListeners();
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _lastError = 'Location permission permanently denied';
      notifyListeners();
      return false;
    }

    _lastError = null;
    return true;
  }

  /// Request current position without starting a session
  /// Used for initial map centering
  Future<void> requestInitialPosition() async {
    if (!await checkPermissions()) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _currentPosition = position;
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _lastError = 'Failed to get location: $e';
      notifyListeners();
    }
  }

  Future<void> start({bool autoMode = false}) async {
    if (_state == WardriveState.running) return;

    if (!await checkPermissions()) return;

    _state = WardriveState.running;
    _sessionStartTime = DateTime.now();
    _lastError = null;

    // Get initial position
    await _updatePosition();
    _startPosition = _currentPosition;

    if (autoMode) {
      _startAutoSampling();
    }

    notifyListeners();
  }

  void pause() {
    if (_state != WardriveState.running) return;
    _state = WardriveState.paused;
    _stopAutoSampling();
    notifyListeners();
  }

  void resume({bool autoMode = false}) {
    if (_state != WardriveState.paused) return;
    _state = WardriveState.running;
    if (autoMode) {
      _startAutoSampling();
    }
    notifyListeners();
  }

  void stop() {
    _state = WardriveState.idle;
    _stopAutoSampling();
    _sessionStartTime = null;
    notifyListeners();
  }

  void reset() {
    stop();
    _samples.clear();
    _coveredTiles.clear();
    _confirmedTiles.clear();
    _sampleCount = 0;
    _distanceTraveled = 0;
    _startPosition = null;
    _currentPosition = null;
    _lastSamplePosition = null;
    _lastError = null;
    _lastSkipReason = null;
    notifyListeners();
  }

  void _startAutoSampling() {
    _stopAutoSampling();

    if (_pingMode == WardrivePingMode.fill) {
      // Fill mode: Check every 10 seconds if we're in a new tile
      _fillModeTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _checkFillMode(),
      );
      // Capture immediately on start
      captureSample(isManual: false);
    } else {
      // Interval mode: Capture at fixed intervals with distance check
      _autoSampleTimer = Timer.periodic(
        Duration(seconds: _autoIntervalSeconds),
        (_) => _checkIntervalMode(),
      );
      // Capture immediately on start
      captureSample(isManual: false);
    }
  }

  void _stopAutoSampling() {
    _autoSampleTimer?.cancel();
    _autoSampleTimer = null;
    _fillModeTimer?.cancel();
    _fillModeTimer = null;
  }

  Future<void> _checkFillMode() async {
    if (_state != WardriveState.running) return;

    await _updatePosition();
    if (_currentPosition == null) return;

    final tileHash = getCoverageTileHash(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    // Check both local and global coverage
    if (_coveredTiles.contains(tileHash) ||
        _globalCoveredTiles.contains(tileHash)) {
      _lastSkipReason = 'Tile already covered ($tileHash)';
      notifyListeners();
      return;
    }

    _lastSkipReason = null;
    await captureSample(isManual: false);
  }

  Future<void> _checkIntervalMode() async {
    if (_state != WardriveState.running) return;

    await _updatePosition();
    if (_currentPosition == null) return;

    // Check minimum distance from last sample
    if (_lastSamplePosition != null) {
      final distance = Geolocator.distanceBetween(
        _lastSamplePosition!.latitude,
        _lastSamplePosition!.longitude,
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      if (distance < _minDistanceMeters) {
        _lastSkipReason = 'Min distance not met (${distance.toStringAsFixed(0)}m < ${_minDistanceMeters.toStringAsFixed(0)}m)';
        notifyListeners();
        return;
      }
    }

    _lastSkipReason = null;
    await captureSample(isManual: false);
  }

  Future<void> _updatePosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (_currentPosition != null) {
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        _distanceTraveled += distance;
      }

      _currentPosition = position;
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _lastError = 'Failed to get location: $e';
      notifyListeners();
    }
  }

  Future<void> captureSample({bool isManual = true}) async {
    if (_state != WardriveState.running) return;

    await _updatePosition();

    if (_currentPosition == null) {
      _lastError = 'No position available';
      notifyListeners();
      return;
    }

    final lat = _currentPosition!.latitude;
    final lon = _currentPosition!.longitude;
    final tileHash = getCoverageTileHash(lat, lon);

    // Create sample with pending status
    var sample = WardriveSample(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.now(),
      isManual: isManual,
      meshStatus: _sendToChannel
          ? SampleDeliveryStatus.pending
          : SampleDeliveryStatus.skipped,
      webStatus:
          _sendToApi ? SampleDeliveryStatus.pending : SampleDeliveryStatus.skipped,
    );

    final sampleIndex = _samples.length;
    _samples.add(sample);
    _sampleCount++;
    notifyListeners();

    // Send to channel if enabled
    if (_sendToChannel) {
      sample = await _sendSampleToChannel(sample);
      _samples[sampleIndex] = sample;
      notifyListeners();
    }

    // Send to API if enabled
    if (_sendToApi) {
      sample = await _sendSampleToApi(sample);
      _samples[sampleIndex] = sample;
      notifyListeners();
    }

    // Mark tile as covered (attempted)
    _coveredTiles.add(tileHash);

    // Mark tile as confirmed if delivery succeeded and refresh coverage data
    if (sample.meshStatus == SampleDeliveryStatus.success ||
        sample.webStatus == SampleDeliveryStatus.success) {
      _confirmedTiles.add(tileHash);
      // Refresh coverage data after successful sample to get latest map data
      unawaited(fetchGlobalCoverage());
    }

    // Remember last sample position for interval mode distance check
    _lastSamplePosition = _currentPosition;
  }

  Future<WardriveSample> _sendSampleToChannel(WardriveSample sample) async {
    if (_connector == null || !_connector!.isConnected) {
      return sample.copyWith(
        meshStatus: SampleDeliveryStatus.failed,
        meshError: 'Not connected to device',
      );
    }

    // Find the channel by name
    final channels = _connector!.channels;
    Channel? targetChannel;

    // Check if channel name starts with # and try to find it
    final searchName =
        _channelName.startsWith('#') ? _channelName.substring(1) : _channelName;

    for (final channel in channels) {
      if (channel.name.toLowerCase() == searchName.toLowerCase() ||
          channel.name.toLowerCase() == _channelName.toLowerCase()) {
        targetChannel = channel;
        break;
      }
    }

    if (targetChannel == null) {
      return sample.copyWith(
        meshStatus: SampleDeliveryStatus.failed,
        meshError: 'Channel "$_channelName" not found',
      );
    }

    try {
      await _connector!.sendChannelMessage(targetChannel, sample.channelMessage);
      return sample.copyWith(meshStatus: SampleDeliveryStatus.success);
    } catch (e) {
      return sample.copyWith(
        meshStatus: SampleDeliveryStatus.failed,
        meshError: 'Failed: $e',
      );
    }
  }

  Future<WardriveSample> _sendSampleToApi(WardriveSample sample) async {
    try {
      final response = await http.post(
        Uri.parse(_apiEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(sample.toJson()),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return sample.copyWith(webStatus: SampleDeliveryStatus.success);
      } else {
        return sample.copyWith(
          webStatus: SampleDeliveryStatus.failed,
          webError: 'HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      return sample.copyWith(
        webStatus: SampleDeliveryStatus.failed,
        webError: 'Failed: $e',
      );
    }
  }

  @override
  void dispose() {
    _stopAutoSampling();
    super.dispose();
  }
}
