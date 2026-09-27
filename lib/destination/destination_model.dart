import '../core/geo_point.dart';

class Destination {
  const Destination({required this.point, required this.createdAt, this.name});

  final GeoPoint point;
  final DateTime createdAt;
  final String? name;

  String get title => name?.trim().isNotEmpty == true ? name!.trim() : point.label;

  Map<String, Object?> toJson() => {
    'latitude': point.latitude,
    'longitude': point.longitude,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static Destination? fromJson(Map<String, dynamic> data) {
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    final createdAt = data['createdAt'];
    if (latitude is! num || longitude is! num || createdAt is! String) {
      return null;
    }
    final point = GeoPoint(latitude.toDouble(), longitude.toDouble());
    final date = DateTime.tryParse(createdAt);
    if (!point.isValid || date == null) return null;
    return Destination(
      point: point,
      createdAt: date,
      name: data['name'] is String ? data['name'] as String : null,
    );
  }
}
