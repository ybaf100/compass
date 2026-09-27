import '../core/geo_point.dart';

class SharedDestination {
  const SharedDestination({
    required this.point,
    required this.updatedBy,
    required this.updatedAt,
    this.name,
  });

  final GeoPoint point;
  final String? name;
  final String updatedBy;
  final DateTime updatedAt;

  String get title => name?.trim().isNotEmpty == true ? name!.trim() : point.label;
}

class Room {
  const Room({
    required this.id,
    required this.inviteCode,
    required this.ownerId,
    required this.createdAt,
    this.sharedDestination,
  });

  final String id;
  final String inviteCode;
  final String ownerId;
  final DateTime createdAt;
  final SharedDestination? sharedDestination;

  static Room fromJson(Map<String, dynamic> json) {
    final latitude = json['destination_latitude'];
    final longitude = json['destination_longitude'];
    final updatedBy = json['destination_updated_by'];
    final updatedAt = DateTime.tryParse('${json['destination_updated_at']}');
    final point = latitude is num && longitude is num
        ? GeoPoint(latitude.toDouble(), longitude.toDouble())
        : null;
    return Room(
      id: json['id'] as String,
      inviteCode: json['invite_code'] as String,
      ownerId: json['owner_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      sharedDestination: point != null && point.isValid &&
              updatedBy is String && updatedAt != null
          ? SharedDestination(
              point: point,
              name: json['destination_name'] as String?,
              updatedBy: updatedBy,
              updatedAt: updatedAt.toUtc(),
            )
          : null,
    );
  }
}
