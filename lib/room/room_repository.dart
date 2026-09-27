import '../core/geo_point.dart';
import 'member_model.dart';
import 'room_model.dart';
import 'shared_ping.dart';

class RoomJoinResult {
  const RoomJoinResult(this.roomId, {this.alreadyJoined = false});
  final String roomId;
  final bool alreadyJoined;
}

class RoomSnapshot {
  const RoomSnapshot({required this.room, required this.members,
    required this.pings});
  final Room room;
  final List<RoomMember> members;
  final List<SharedPing> pings;
}

abstract class RoomRepository {
  String? get userId;
  Future<String> ensureIdentity();
  Future<RoomJoinResult> createRoom(String nickname);
  Future<RoomJoinResult> joinRoom(String code, String nickname);
  Future<RoomSnapshot> loadSnapshot(String roomId);
  Stream<Room> watchRoom(String roomId);
  Stream<List<RoomMember>> watchMembers(String roomId);
  Stream<List<SharedPing>> watchPings(String roomId);
  Future<void> updateLocation(String roomId, GeoPoint point, double accuracy);
  Future<void> updateNickname(String roomId, String nickname);
  Future<void> sendPing(String roomId, GeoPoint point);
  Future<void> setSharedDestination(String roomId, GeoPoint point, String? name);
  Future<void> leaveRoom(String roomId);
}
