import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/geo_point.dart';
import '../core/location/location_provider.dart';
import '../destination/bearing_engine.dart';
import 'member_model.dart';
import 'profile_store.dart';
import 'room_model.dart';
import 'room_repository.dart';
import 'shared_ping.dart';

class RoomController extends ChangeNotifier {
  RoomController({
    required RoomRepository? repository,
    required ProfileStore profileStore,
    required Listenable locationChanges,
    required LocationFix? Function() currentLocation,
    required bool? Function() hasNetwork,
    DateTime Function()? now,
  }) : _repository = repository,
       _profileStore = profileStore,
       _locationChanges = locationChanges,
       _currentLocation = currentLocation,
       _hasNetwork = hasNetwork,
       _now = now ?? DateTime.now;

  static const uploadInterval = Duration(seconds: 8);
  static const minimumUploadInterval = Duration(seconds: 2);
  static const minimumMovementMeters = 8.0;
  static const maximumUploadAccuracyMeters = 80.0;
  static const staleAfter = Duration(seconds: 35);
  static const pingLifetime = Duration(minutes: 30);

  final RoomRepository? _repository;
  final ProfileStore _profileStore;
  final Listenable _locationChanges;
  final LocationFix? Function() _currentLocation;
  final bool? Function() _hasNetwork;
  final DateTime Function() _now;

  String? nickname;
  String? userId;
  Room? room;
  List<RoomMember> members = const [];
  List<SharedPing> pings = const [];
  String? error;
  bool busy = false;
  bool foreground = true;
  bool _disposed = false;
  bool _started = false;
  bool? _lastNetwork;
  int _generation = 0;
  DateTime? _lastUploadAt;
  DateTime? _lastSuccessfulUploadAt;
  GeoPoint? _lastUploadPoint;
  bool _uploading = false;
  Timer? _ticker;
  StreamSubscription<Room>? _roomSubscription;
  StreamSubscription<List<RoomMember>>? _membersSubscription;
  StreamSubscription<List<SharedPing>>? _pingsSubscription;
  String? _pendingLeave;

  bool get configured => _repository != null;
  bool get sharingLocation => room != null && foreground &&
      _lastSuccessfulUploadAt != null &&
      currentTime.difference(_lastSuccessfulUploadAt!) < staleAfter;
  DateTime get currentTime => _now().toUtc();
  List<SharedPing> get activePings => pings
      .where((ping) => currentTime.difference(ping.createdAt) < pingLifetime)
      .take(20).toList();

  RoomMember? member(String id) {
    for (final member in members) {
      if (member.userId == id) return member;
    }
    return null;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _locationChanges.addListener(_onLocationChanged);
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (room == null || _disposed) return;
      _notify(); // Age labels, stale state and ping expiry need a clock tick.
      _maybeUpload();
    });
    nickname = await _profileStore.loadNickname();
    _pendingLeave = await _profileStore.loadPendingLeave();
    final savedRoom = await _profileStore.loadRoomId();
    if (_disposed) return;
    _notify();
    if (_repository == null) return;
    try {
      if (savedRoom != null || _pendingLeave != null) {
        userId = await _repository.ensureIdentity();
      }
      await _retryPendingLeave();
      if (savedRoom != null && !_disposed) await _activate(savedRoom);
    } catch (e) {
      if (!_disposed) {
        error = '방 연결에 실패했습니다. 연결을 확인하고 다시 시도하세요.';
        _notify();
      }
    }
  }

  Future<void> setNickname(String value) async {
    final name = value.trim();
    if (name.isEmpty || name.length > 24) {
      throw StateError('닉네임은 1~24자로 입력하세요.');
    }
    await _profileStore.saveNickname(name);
    nickname = name;
    _notify();
    final activeRoom = room;
    if (activeRoom != null) {
      await _repository!.updateNickname(activeRoom.id, name);
    }
  }

  Future<RoomJoinResult> createRoom() => _enter(
      (repo, name) => repo.createRoom(name));

  Future<RoomJoinResult> joinRoom(String code) {
    final normalized = code.trim().toUpperCase();
    if (!RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(normalized)) {
      throw StateError('초대 코드는 영문·숫자 6자리입니다.');
    }
    return _enter((repo, name) => repo.joinRoom(normalized, name));
  }

  Future<RoomJoinResult> _enter(Future<RoomJoinResult> Function(
      RoomRepository, String) action) async {
    final repo = _repository;
    if (repo == null) throw StateError('Supabase 설정이 필요합니다.');
    if (room != null) throw StateError('이미 방에 참가 중입니다.');
    if (busy) throw StateError('방 연결 중입니다.');
    final name = nickname;
    if (name == null || name.isEmpty) throw StateError('닉네임을 먼저 설정하세요.');
    busy = true;
    error = null;
    _notify();
    try {
      await _retryPendingLeave();
      userId = await repo.ensureIdentity();
      final result = await action(repo, name);
      await _activate(result.roomId);
      return result;
    } catch (e) {
      error = readableError(e);
      _notify();
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _activate(String id) async {
    final generation = ++_generation;
    await _cancelSubscriptions();
    final snapshot = await _repository!.loadSnapshot(id);
    if (_disposed || generation != _generation) return;
    room = snapshot.room;
    members = snapshot.members;
    pings = snapshot.pings;
    userId = _repository.userId;
    _lastUploadAt = null;
    _lastSuccessfulUploadAt = null;
    _lastUploadPoint = null;
    error = null;
    await _profileStore.saveRoomId(id);
    if (_disposed || generation != _generation) return;
    _subscribe(id, generation);
    _notify();
    _maybeUpload();
  }

  void _subscribe(String id, int generation) {
    final repo = _repository!;
    void onError(Object exception) {
      if (_disposed || generation != _generation) return;
      error = '실시간 연결이 끊겼습니다. 재연결을 시도하세요.';
      _notify();
    }
    _roomSubscription = repo.watchRoom(id).listen((value) {
      if (_disposed || generation != _generation) return;
      room = value;
      error = null;
      _notify();
    }, onError: onError);
    _membersSubscription = repo.watchMembers(id).listen((value) {
      if (_disposed || generation != _generation) return;
      members = value;
      error = null;
      _notify();
    }, onError: onError);
    _pingsSubscription = repo.watchPings(id).listen((value) {
      if (_disposed || generation != _generation) return;
      pings = value;
      error = null;
      _notify();
    }, onError: onError);
  }

  Future<void> reconnect() async {
    final id = room?.id ?? await _profileStore.loadRoomId();
    if (_disposed || _repository == null) return;
    try {
      await _retryPendingLeave();
      if (id != null) {
        userId = await _repository.ensureIdentity();
        await _activate(id); // Fresh PostgREST snapshot, then new subscriptions.
      }
    } catch (_) {
      if (_disposed) return;
      error = '방에 다시 연결하지 못했습니다. 연결을 확인하세요.';
      _notify();
    }
  }

  void setForeground(bool active) {
    foreground = active;
    if (active) {
      unawaited(reconnect());
    }
    _notify();
  }

  void _onLocationChanged() {
    final network = _hasNetwork();
    if (_lastNetwork == false && network == true && room != null) {
      unawaited(reconnect());
    }
    _lastNetwork = network;
    _maybeUpload();
  }

  void _maybeUpload() {
    final id = room?.id;
    final fix = _currentLocation();
    if (id == null || fix == null || !foreground || _uploading ||
        _hasNetwork() == false || !fix.point.isValid ||
        fix.accuracyMeters > maximumUploadAccuracyMeters ||
        fix.accuracyMeters < 0) {
      return;
    }
    final now = currentTime;
    final elapsed = _lastUploadAt == null
        ? null : now.difference(_lastUploadAt!);
    if (elapsed != null && elapsed < minimumUploadInterval) return;
    final moved = _lastUploadPoint != null &&
        BearingEngine.distanceMeters(_lastUploadPoint!, fix.point) >=
            minimumMovementMeters;
    if (elapsed != null && !moved && elapsed < uploadInterval) return;
    _uploading = true;
    _lastUploadAt = now;
    _lastUploadPoint = fix.point;
    unawaited(_repository!.updateLocation(id, fix.point,
        fix.accuracyMeters).then((_) {
      if (room?.id == id && !_disposed) {
        _lastSuccessfulUploadAt = currentTime;
        _notify();
      }
    }).catchError((Object _) {
      if (room?.id == id && !_disposed) {
        _lastUploadAt = null;
        error = '위치 공유에 실패했습니다. 연결을 확인하세요.';
        _notify();
      }
    }).whenComplete(() {
      _uploading = false;
    }));
  }

  Future<void> sendPing(GeoPoint point) async {
    final id = room?.id;
    if (id == null) throw StateError('방에 참가한 후 Ping을 보낼 수 있습니다.');
    await _repository!.sendPing(id, point);
  }

  Future<void> setSharedDestination(GeoPoint point, String? name) async {
    final id = room?.id;
    if (id == null) throw StateError('방에 참가한 후 공유할 수 있습니다.');
    await _repository!.setSharedDestination(id, point, name);
  }

  Future<void> leave() async {
    final id = room?.id;
    if (id == null) return;
    ++_generation;
    room = null; // Stop all future uploads before any await.
    members = const [];
    pings = const [];
    _lastUploadAt = null;
    _lastSuccessfulUploadAt = null;
    _lastUploadPoint = null;
    _notify();
    await _cancelSubscriptions();
    _pendingLeave = id;
    await _profileStore.savePendingLeave(id);
    await _profileStore.saveRoomId(null);
    try {
      await _retryPendingLeave();
      error = null;
    } catch (_) {
      error = '방 나가기를 서버에 반영하지 못했습니다. 재연결 시 다시 시도합니다.';
    }
    _notify();
  }

  Future<void> _retryPendingLeave() async {
    final id = _pendingLeave;
    if (id == null || _repository == null) return;
    await _repository.leaveRoom(id);
    if (_disposed || _pendingLeave != id) return;
    _pendingLeave = null;
    await _profileStore.savePendingLeave(null);
  }

  Future<void> _cancelSubscriptions() async {
    await _roomSubscription?.cancel();
    await _membersSubscription?.cancel();
    await _pingsSubscription?.cancel();
    _roomSubscription = null;
    _membersSubscription = null;
    _pingsSubscription = null;
  }

  static String readableError(Object exception) {
    final detail = exception.toString();
    if (detail.contains('invalid_invite_code')) return '초대 코드 형식이 잘못되었습니다.';
    if (detail.contains('room_not_found')) return '존재하지 않는 방입니다.';
    if (detail.contains('not_room_member')) return '방 참가 정보가 유효하지 않습니다.';
    if (exception is StateError) return exception.message.toString();
    return '요청에 실패했습니다. 네트워크와 방 설정을 확인하세요.';
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    room = null;
    _ticker?.cancel();
    _locationChanges.removeListener(_onLocationChanged);
    unawaited(_cancelSubscriptions());
    super.dispose();
  }
}
