/// Delivery status for wardrive samples
enum SampleDeliveryStatus {
  pending,
  success,
  failed,
  skipped,
}

/// Represents a single wardrive sample with GPS location and delivery status
class WardriveSample {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final SampleDeliveryStatus meshStatus;
  final SampleDeliveryStatus webStatus;
  final String? meshError;
  final String? webError;
  final bool isManual;

  WardriveSample({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.meshStatus = SampleDeliveryStatus.pending,
    this.webStatus = SampleDeliveryStatus.pending,
    this.meshError,
    this.webError,
    this.isManual = true,
  });

  /// Whether this sample was sent to the channel successfully
  bool get sentToChannel => meshStatus == SampleDeliveryStatus.success;

  /// Whether this sample was sent to the API successfully
  bool get sentToApi => webStatus == SampleDeliveryStatus.success;

  WardriveSample copyWith({
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    SampleDeliveryStatus? meshStatus,
    SampleDeliveryStatus? webStatus,
    String? meshError,
    String? webError,
    bool? isManual,
  }) {
    return WardriveSample(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      meshStatus: meshStatus ?? this.meshStatus,
      webStatus: webStatus ?? this.webStatus,
      meshError: meshError ?? this.meshError,
      webError: webError ?? this.webError,
      isManual: isManual ?? this.isManual,
    );
  }

  Map<String, dynamic> toJson() => {
        'lat': double.parse(latitude.toStringAsFixed(4)),
        'lon': double.parse(longitude.toStringAsFixed(4)),
      };

  String get channelMessage =>
      '${latitude.toStringAsFixed(4)} ${longitude.toStringAsFixed(4)}';

  String get coordinatesDisplay =>
      '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';

  String get timeDisplay {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  String toString() =>
      'WardriveSample($latitude, $longitude, mesh: $meshStatus, web: $webStatus)';
}
