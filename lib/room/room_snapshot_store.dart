import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'room_model.dart';
import 'member_model.dart';
import 'room_repository.dart';
import 'shared_ping.dart';

abstract class RoomSnapshotStore {
  Future<RoomSnapshot?> load();
  Future<void> save(RoomSnapshot? snapshot);
}

/// Read-only offline cache; mutations are never queued for later upload.
class PreferencesRoomSnapshotStore implements RoomSnapshotStore {
  static const key = 'room.last_snapshot_v1';

  @override
  Future<RoomSnapshot?> load() async {
    final encoded = (await SharedPreferences.getInstance()).getString(key);
    if (encoded == null) return null;
    try {
      final json = jsonDecode(encoded) as Map<String, dynamic>;
      return RoomSnapshot(
        room: Room.fromJson(json['room'] as Map<String, dynamic>),
        members: (json['members'] as List).map((value) =>
          RoomMember.fromJson(value as Map<String, dynamic>)).toList(),
        pings: (json['pings'] as List).map((value) =>
          SharedPing.fromJson(value as Map<String, dynamic>)).toList());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(RoomSnapshot? snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    if (snapshot == null) {
      await prefs.remove(key);
      return;
    }
    final room = snapshot.room;
    final shared = room.sharedDestination;
    await prefs.setString(key, jsonEncode({
      'room': {
        'id': room.id, 'invite_code': room.inviteCode,
        'owner_id': room.ownerId,
        'created_at': room.createdAt.toUtc().toIso8601String(),
        'destination_latitude': shared?.point.latitude,
        'destination_longitude': shared?.point.longitude,
        'destination_name': shared?.name,
        'destination_updated_by': shared?.updatedBy,
        'destination_updated_at': shared?.updatedAt.toUtc().toIso8601String(),
      },
      'members': [for (final member in snapshot.members) {
        'user_id': member.userId, 'nickname': member.nickname,
        'latitude': member.point?.latitude,
        'longitude': member.point?.longitude,
        'accuracy': member.accuracyMeters,
        'updated_at': member.updatedAt.toUtc().toIso8601String(),
      }],
      'pings': [for (final ping in snapshot.pings) {
        'id': ping.id, 'latitude': ping.point.latitude,
        'longitude': ping.point.longitude, 'created_by': ping.createdBy,
        'created_by_nickname': ping.createdByNickname,
        'created_at': ping.createdAt.toUtc().toIso8601String(),
      }],
    }));
  }
}
