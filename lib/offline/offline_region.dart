import 'dart:math' as math;

import '../core/geo_point.dart';
import '../destination/bearing_engine.dart';

enum OfflineRegionStatus { ready, downloading, failed }

/// A geodesic circle, persisted separately from Mapbox's tile-region index.
class OfflineRegion {
  const OfflineRegion({required this.id, required this.name,
    required this.center, required this.radiusMeters, required this.minZoom,
    required this.maxZoom, required this.status, this.downloadedAt,
    this.sizeBytes = 0, this.failure});

  final String id;
  final String name;
  final GeoPoint center;
  final double radiusMeters;
  final int minZoom;
  final int maxZoom;
  final OfflineRegionStatus status;
  final DateTime? downloadedAt;
  final int sizeBytes;
  final String? failure;

  bool contains(GeoPoint point) => status == OfflineRegionStatus.ready &&
      BearingEngine.distanceMeters(center, point) <= radiusMeters;

  /// GeoJSON ring; the same geometry is used for downloads and coverage.
  List<List<double>> get ring {
    const segments = 64;
    const earthRadius = 6371000.0;
    final latitude = center.latitude * math.pi / 180;
    final longitude = center.longitude * math.pi / 180;
    final distance = radiusMeters / earthRadius;
    final positions = <List<double>>[];
    for (var index = 0; index < segments; index++) {
      final bearing = 2 * math.pi * index / segments;
      final lat = math.asin(math.sin(latitude) * math.cos(distance) +
          math.cos(latitude) * math.sin(distance) * math.cos(bearing));
      final lon = longitude + math.atan2(math.sin(bearing) *
          math.sin(distance) * math.cos(latitude), math.cos(distance) -
          math.sin(latitude) * math.sin(lat));
      positions.add([((lon * 180 / math.pi + 540) % 360) - 180,
          lat * 180 / math.pi]);
    }
    positions.add(positions.first);
    return positions;
  }

  OfflineRegion copyWith({OfflineRegionStatus? status, DateTime? downloadedAt,
      int? sizeBytes, String? failure}) => OfflineRegion(
    id: id, name: name, center: center, radiusMeters: radiusMeters,
    minZoom: minZoom, maxZoom: maxZoom, status: status ?? this.status,
    downloadedAt: downloadedAt ?? this.downloadedAt,
    sizeBytes: sizeBytes ?? this.sizeBytes, failure: failure,
  );

  Map<String, Object?> toJson() => {
    'id': id, 'name': name, 'latitude': center.latitude,
    'longitude': center.longitude, 'radiusMeters': radiusMeters,
    'minZoom': minZoom, 'maxZoom': maxZoom, 'status': status.name,
    'downloadedAt': downloadedAt?.toUtc().toIso8601String(),
    'sizeBytes': sizeBytes, 'failure': failure,
  };

  static OfflineRegion? fromJson(Map<String, dynamic> json) {
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    final radius = json['radiusMeters'];
    final id = json['id'];
    if (latitude is! num || longitude is! num || radius is! num ||
        id is! String || radius <= 0) {
      return null;
    }
    final center = GeoPoint(latitude.toDouble(), longitude.toDouble());
    if (!center.isValid) return null;
    final status = OfflineRegionStatus.values.where(
        (value) => value.name == json['status']).firstOrNull;
    return OfflineRegion(id: id, name: json['name'] is String
        ? json['name'] as String : center.label,
      center: center, radiusMeters: radius.toDouble(),
      minZoom: (json['minZoom'] as num?)?.toInt() ?? 0,
      maxZoom: (json['maxZoom'] as num?)?.toInt() ?? 15,
      // An interrupted download must be retried, never advertised as complete.
      status: status == OfflineRegionStatus.downloading
          ? OfflineRegionStatus.failed : status ?? OfflineRegionStatus.failed,
      downloadedAt: DateTime.tryParse('${json['downloadedAt']}')?.toUtc(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      failure: json['failure'] as String?);
  }
}
