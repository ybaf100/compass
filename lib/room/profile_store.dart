import 'package:shared_preferences/shared_preferences.dart';

abstract class ProfileStore {
  Future<String?> loadNickname();
  Future<void> saveNickname(String nickname);
  Future<String?> loadRoomId();
  Future<void> saveRoomId(String? roomId);
  Future<String?> loadPendingLeave();
  Future<void> savePendingLeave(String? roomId);
}

class PreferencesProfileStore implements ProfileStore {
  static const _nicknameKey = 'room.nickname';
  static const _roomKey = 'room.active_id';
  static const _pendingKey = 'room.pending_leave';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> loadNickname() async => (await _prefs).getString(_nicknameKey);

  @override
  Future<void> saveNickname(String nickname) async {
    await (await _prefs).setString(_nicknameKey, nickname);
  }

  @override
  Future<String?> loadRoomId() async => (await _prefs).getString(_roomKey);

  @override
  Future<void> saveRoomId(String? roomId) async {
    final prefs = await _prefs;
    if (roomId == null) {
      await prefs.remove(_roomKey);
    } else {
      await prefs.setString(_roomKey, roomId);
    }
  }

  @override
  Future<String?> loadPendingLeave() async =>
      (await _prefs).getString(_pendingKey);

  @override
  Future<void> savePendingLeave(String? roomId) async {
    final prefs = await _prefs;
    if (roomId == null) {
      await prefs.remove(_pendingKey);
    } else {
      await prefs.setString(_pendingKey, roomId);
    }
  }
}
