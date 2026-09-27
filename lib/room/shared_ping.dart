import '../core/geo_point.dart';

class SharedPing {
  const SharedPing({
    required this.id,
    required this.point,
    required this.createdBy,
    required this.createdByNickname,
    required this.createdAt,
  });

  final String id;
  final GeoPoint point;
  final String createdBy;
  final String createdByNickname;
  final DateTime createdAt;

  static SharedPing fromJson(Map<String, dynamic> json) => SharedPing(
    id: json['id'] as String,
    point: GeoPoint((json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble()),
    createdBy: json['created_by'] as String,
    createdByNickname: json['created_by_nickname'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
  );
}
