import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/geo_point.dart';
import 'member_model.dart';
import 'room_model.dart';
import 'room_repository.dart';
import 'shared_ping.dart';

/// All database names and Supabase types remain inside this adapter.
class RealtimeRoomRepository implements RoomRepository {
  RealtimeRoomRepository(this._client);

  final SupabaseClient _client;

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  Future<String> ensureIdentity() async {
    final existing = userId;
    if (existing != null) return existing;
    final response = await _client.auth.signInAnonymously();
    final id = response.user?.id;
    if (id == null) throw StateError('익명 사용자 인증에 실패했습니다.');
    return id;
  }

  @override
  Future<RoomJoinResult> createRoom(String nickname) async {
    await ensureIdentity();
    final data = await _client.rpc('create_compass_room',
        params: {'p_nickname': nickname});
    return _joinResult(Map<String, dynamic>.from(data as Map));
  }

  @override
  Future<RoomJoinResult> joinRoom(String code, String nickname) async {
    await ensureIdentity();
    final data = await _client.rpc('join_compass_room',
        params: {'p_code': code, 'p_nickname': nickname});
    return _joinResult(Map<String, dynamic>.from(data as Map));
  }

  static RoomJoinResult _joinResult(Map<String, dynamic> data) => RoomJoinResult(
    data['room_id'] as String,
    alreadyJoined: data['already_joined'] == true,
  );

  @override
  Future<RoomSnapshot> loadSnapshot(String roomId) async {
    final room = await _client.from('rooms').select()
        .eq('id', roomId).single();
    final members = await _client.from('room_members').select()
        .eq('room_id', roomId);
    final pings = await _client.from('shared_pings').select()
        .eq('room_id', roomId).order('created_at', ascending: false).limit(20);
    return RoomSnapshot(
      room: Room.fromJson(room),
      members: members.map(RoomMember.fromJson).toList(),
      pings: pings.map(SharedPing.fromJson).toList(),
    );
  }

  @override
  Stream<Room> watchRoom(String roomId) => _client.from('rooms')
      .stream(primaryKey: ['id']).eq('id', roomId)
      .map((rows) => Room.fromJson(rows.single));

  @override
  Stream<List<RoomMember>> watchMembers(String roomId) => _client
      .from('room_members').stream(primaryKey: ['room_id', 'user_id'])
      .eq('room_id', roomId)
      .map((rows) => rows.map(RoomMember.fromJson).toList());

  @override
  Stream<List<SharedPing>> watchPings(String roomId) => _client
      .from('shared_pings').stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .map((rows) => rows.map(SharedPing.fromJson).toList());

  @override
  Future<void> updateLocation(String roomId, GeoPoint point,
      double accuracy) async {
    await _client.rpc('update_compass_location', params: {
      'p_room_id': roomId,
      'p_latitude': point.latitude,
      'p_longitude': point.longitude,
      'p_accuracy': accuracy,
    });
  }

  @override
  Future<void> updateNickname(String roomId, String nickname) async {
    await _client.rpc('update_compass_nickname', params: {
      'p_room_id': roomId, 'p_nickname': nickname,
    });
  }

  @override
  Future<void> sendPing(String roomId, GeoPoint point) async {
    await _client.rpc('send_compass_ping', params: {
      'p_room_id': roomId,
      'p_latitude': point.latitude,
      'p_longitude': point.longitude,
    });
  }

  @override
  Future<void> setSharedDestination(String roomId, GeoPoint point,
      String? name) async {
    await _client.rpc('set_compass_destination', params: {
      'p_room_id': roomId,
      'p_latitude': point.latitude,
      'p_longitude': point.longitude,
      'p_name': name,
    });
  }

  @override
  Future<void> leaveRoom(String roomId) async {
    await _client.rpc('leave_compass_room', params: {'p_room_id': roomId});
  }
}
