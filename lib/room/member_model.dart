import '../core/geo_point.dart';

class RoomMember {
  const RoomMember({
    required this.userId,
    required this.nickname,
    required this.updatedAt,
    this.point,
    this.accuracyMeters,
  });

  final String userId;
  final String nickname;
  final GeoPoint? point;
  final double? accuracyMeters;
  final DateTime updatedAt;

  bool isStale(DateTime now, Duration threshold) =>
      point == null || now.difference(updatedAt) > threshold;

  static RoomMember fromJson(Map<String, dynamic> json) {
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    final point = latitude is num && longitude is num
        ? GeoPoint(latitude.toDouble(), longitude.toDouble())
        : null;
    return RoomMember(
      userId: json['user_id'] as String,
      nickname: json['nickname'] as String,
      point: point?.isValid == true ? point : null,
      accuracyMeters: (json['accuracy'] as num?)?.toDouble(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    );
  }
}
