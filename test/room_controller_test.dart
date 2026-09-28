import 'dart:async';

import 'package:destination_compass/core/compass/heading_provider.dart';
import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/core/location/location_provider.dart';
import 'package:destination_compass/core/network/network_monitor.dart';
import 'package:destination_compass/destination/destination_controller.dart';
import 'package:destination_compass/destination/destination_model.dart';
import 'package:destination_compass/destination/destination_store.dart';
import 'package:destination_compass/navigation/navigation_target.dart';
import 'package:destination_compass/room/member_model.dart';
import 'package:destination_compass/room/profile_store.dart';
import 'package:destination_compass/room/room_controller.dart';
import 'package:destination_compass/room/room_model.dart';
import 'package:destination_compass/room/room_repository.dart';
import 'package:destination_compass/room/shared_ping.dart';
import 'package:destination_compass/room/room_snapshot_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Clock {
  DateTime now = DateTime.utc(2026, 9, 27, 12);
  void advance(Duration by) => now = now.add(by);
}

class _Backend {
  _Backend(this.clock);
  final _Clock clock;
  Room? room;
  final Map<String, RoomMember> members = {};
  final List<SharedPing> pings = [];
  final roomEvents = StreamController<Room>.broadcast();
  final memberEvents = StreamController<List<RoomMember>>.broadcast();
  final pingEvents = StreamController<List<SharedPing>>.broadcast();
  int leaves = 0;
  int writes = 0;
  bool failLeave = false;
  bool offline = false;

  void publishMembers() => memberEvents.add(members.values.toList());
  void dispose() {
    roomEvents.close();
    memberEvents.close();
    pingEvents.close();
  }
}

class _Repository implements RoomRepository {
  _Repository(this.backend, this.id);
  final _Backend backend;
  final String id;
  @override
  String? get userId => id;
  @override
  Future<String> ensureIdentity() async => id;
  @override
  Future<RoomJoinResult> createRoom(String nickname) async {
    backend.room = Room(id: 'room1', inviteCode: 'ABC234', ownerId: id,
      createdAt: backend.clock.now);
    backend.members[id] = RoomMember(userId: id, nickname: nickname,
      updatedAt: backend.clock.now);
    backend.publishMembers();
    return const RoomJoinResult('room1');
  }
  @override
  Future<RoomJoinResult> joinRoom(String code, String nickname) async {
    if (code != backend.room?.inviteCode) throw StateError('room_not_found');
    final already = backend.members.containsKey(id);
    backend.members[id] = RoomMember(userId: id, nickname: nickname,
      updatedAt: backend.clock.now);
    backend.publishMembers();
    return RoomJoinResult('room1', alreadyJoined: already);
  }
  @override
  Future<RoomSnapshot> loadSnapshot(String roomId) async {
    if (backend.offline) throw StateError('offline');
    return RoomSnapshot(room: backend.room!,
      members: backend.members.values.toList(), pings: backend.pings.toList());
  }
  @override
  Stream<Room> watchRoom(String roomId) async* {
    yield backend.room!;
    yield* backend.roomEvents.stream;
  }
  @override
  Stream<List<RoomMember>> watchMembers(String roomId) async* {
    yield backend.members.values.toList();
    yield* backend.memberEvents.stream;
  }
  @override
  Stream<List<SharedPing>> watchPings(String roomId) async* {
    yield backend.pings.toList();
    yield* backend.pingEvents.stream;
  }
  @override
  Future<void> updateLocation(String roomId, GeoPoint point, double accuracy) async {
    backend.writes++;
    final previous = backend.members[id]!;
    backend.members[id] = RoomMember(userId: id, nickname: previous.nickname,
      point: point, accuracyMeters: accuracy,
      updatedAt: backend.clock.now);
    backend.publishMembers();
  }
  @override
  Future<void> updateNickname(String roomId, String nickname) async {
    final previous = backend.members[id]!;
    backend.members[id] = RoomMember(userId: id, nickname: nickname,
      point: previous.point, updatedAt: previous.updatedAt);
    backend.publishMembers();
  }
  @override
  Future<void> setSharedDestination(String roomId, GeoPoint point,
      String? name) async {
    backend.room = Room(id: roomId, inviteCode: 'ABC234', ownerId: 'a',
      createdAt: backend.room!.createdAt,
      sharedDestination: SharedDestination(point: point, name: name,
        updatedBy: id, updatedAt: backend.clock.now));
    backend.roomEvents.add(backend.room!);
  }
  @override
  Future<void> sendPing(String roomId, GeoPoint point) async {
    backend.pings.insert(0, SharedPing(id: 'ping${backend.pings.length}',
      point: point, createdBy: id,
      createdByNickname: backend.members[id]!.nickname,
      createdAt: backend.clock.now));
    backend.pingEvents.add(backend.pings.toList());
  }
  @override
  Future<void> leaveRoom(String roomId) async {
    if (backend.failLeave) throw StateError('offline');
    backend.leaves++;
    backend.members.remove(id);
    backend.publishMembers();
  }
}

class _Store implements ProfileStore {
  String? nickname;
  String? roomId;
  String? pending;
  @override
  Future<String?> loadNickname() async => nickname;
  @override
  Future<void> saveNickname(String name) async { nickname = name; }
  @override
  Future<String?> loadRoomId() async => roomId;
  @override
  Future<void> saveRoomId(String? value) async { roomId = value; }
  @override
  Future<String?> loadPendingLeave() async => pending;
  @override
  Future<void> savePendingLeave(String? value) async { pending = value; }
}

class _SnapshotStore implements RoomSnapshotStore {
  RoomSnapshot? value;
  @override
  Future<RoomSnapshot?> load() async => value;
  @override
  Future<void> save(RoomSnapshot? snapshot) async => value = snapshot;
}

class _Signals extends ChangeNotifier {
  void tick() => notifyListeners();
}
class _Location implements LocationProvider {
  @override
  Future<LocationAccess> checkAccess({required bool requestPermission}) async =>
      LocationAccess.denied;
  @override
  Stream<LocationFix> get positions => const Stream.empty();
  @override
  Stream<bool> get serviceEnabled => const Stream.empty();
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> openLocationSettings() async {}
}
class _Heading implements HeadingProvider {
  @override
  Stream<HeadingReading?> get heading => const Stream.empty();
  @override
  Future<void> updateLocation(double latitude, double longitude,
      double altitude) async {}
}
class _Network implements NetworkMonitor {
  @override
  Future<bool> get hasConnection async => true;
  @override
  Stream<bool> get changes => const Stream.empty();
}
class _DestinationStore implements DestinationStore {
  @override
  Future<Destination?> load() async => null;
  @override
  Future<void> save(Destination? destination) async {}
}

Future<void> flush() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  test('two clients create/join, receive ping and shared target, follow moving member', () async {
    final clock = _Clock();
    final backend = _Backend(clock);
    final aSignals = _Signals(), bSignals = _Signals();
    LocationFix? aFix, bFix;
    final a = RoomController(repository: _Repository(backend, 'a'),
      profileStore: _Store(), locationChanges: aSignals,
      currentLocation: () => aFix, hasNetwork: () => true,
      now: () => clock.now);
    final b = RoomController(repository: _Repository(backend, 'b'),
      profileStore: _Store(), locationChanges: bSignals,
      currentLocation: () => bFix, hasNetwork: () => true,
      now: () => clock.now);
    final personal = DestinationController(locationProvider: _Location(),
      headingProvider: _Heading(), networkMonitor: _Network(),
      store: _DestinationStore());
    personal.destination = Destination(point: const GeoPoint(37.5, 127.0),
      createdAt: clock.now, name: '내 장소');
    personal.location = const LocationFix(point: GeoPoint(37.5, 127),
      accuracyMeters: 10, altitudeMeters: 0);
    final navigation = NavigationTargetController(personal, b);
    await a.start(); await b.start();
    await a.setNickname('환희'); await b.setNickname('철수');
    expect(a.userId, 'a');
    expect(b.userId, 'b');
    final created = await a.createRoom();
    expect(created.roomId, 'room1');
    await b.joinRoom(a.room!.inviteCode);
    await flush();
    expect(a.members.length, 2);
    expect(b.members.length, 2);
    expect(navigation.target?.title, '내 장소');
    aFix = const LocationFix(point: GeoPoint(37.51, 127.01),
      accuracyMeters: 10, altitudeMeters: 0);
    bFix = personal.location;
    aSignals.tick(); bSignals.tick();
    await flush();
    expect(backend.writes, 2);
    await a.sendPing(const GeoPoint(37.52, 127.02));
    await flush();
    expect(b.activePings.single.createdByNickname, '환희');
    clock.advance(const Duration(seconds: 1));
    await a.setSharedDestination(const GeoPoint(37.53, 127.03), '서울숲');
    await flush();
    expect(navigation.mode, TargetMode.shared);
    expect(navigation.target?.point, const GeoPoint(37.53, 127.03));
    navigation.followMember('a');
    expect(navigation.target?.point, const GeoPoint(37.51, 127.01));
    clock.advance(const Duration(seconds: 9));
    aFix = const LocationFix(point: GeoPoint(37.54, 127.04),
      accuracyMeters: 10, altitudeMeters: 0);
    aSignals.tick(); await flush();
    expect(navigation.target?.point, const GeoPoint(37.54, 127.04));
    expect(navigation.distanceMeters, greaterThan(0));
    clock.advance(const Duration(seconds: 40));
    expect(navigation.target?.notice, contains('오래되었습니다'));
    clock.advance(const Duration(minutes: 31));
    expect(b.activePings, isEmpty);
    navigation.selectPersonal();
    expect(navigation.target?.title, '내 장소');
    final beforeLeave = backend.writes;
    await a.leave();
    aSignals.tick(); await flush();
    expect(a.sharingLocation, false);
    expect(backend.writes, beforeLeave);
    expect(backend.leaves, 1);
    navigation.dispose(); personal.dispose();
    a.dispose(); b.dispose(); aSignals.dispose(); bSignals.dispose();
    backend.dispose();
  });

  test('invalid code, poor accuracy and duplicate join are handled', () async {
    final clock = _Clock(); final backend = _Backend(clock);
    final signals = _Signals();
    LocationFix? fix = const LocationFix(point: GeoPoint(37, 127),
      accuracyMeters: 200, altitudeMeters: 0);
    final a = RoomController(repository: _Repository(backend, 'a'),
      profileStore: _Store(), locationChanges: signals,
      currentLocation: () => fix, hasNetwork: () => true, now: () => clock.now);
    await a.start(); await a.setNickname('환희');
    expect(() => a.joinRoom('BAD'), throwsStateError);
    await a.createRoom();
    signals.tick(); await flush();
    expect(backend.writes, 0);
    fix = const LocationFix(point: GeoPoint(37, 127),
      accuracyMeters: 10, altitudeMeters: 0);
    signals.tick(); await flush();
    expect(backend.writes, 1);
    signals.tick(); await flush();
    expect(backend.writes, 1);
    await a.leave();
    final result = await a.joinRoom('ABC234');
    expect(result.alreadyJoined, false);
    a.dispose(); signals.dispose(); backend.dispose();
  });

  test('failed leave stops sharing and retries remote cleanup on reconnect', () async {
    final clock = _Clock(); final backend = _Backend(clock);
    final signals = _Signals(); final store = _Store();
    LocationFix? fix = const LocationFix(point: GeoPoint(37, 127),
      accuracyMeters: 10, altitudeMeters: 0);
    final a = RoomController(repository: _Repository(backend, 'a'),
      profileStore: store, locationChanges: signals,
      currentLocation: () => fix, hasNetwork: () => true, now: () => clock.now);
    await a.start(); await a.setNickname('환희'); await a.createRoom();
    await flush();
    backend.room = Room(id: 'room1', inviteCode: 'ABC234', ownerId: 'a',
      createdAt: backend.room!.createdAt,
      sharedDestination: SharedDestination(point: const GeoPoint(37.2, 127.2),
        updatedBy: 'a', updatedAt: clock.now, name: '새 목적지'));
    await a.reconnect(); // The changed row was not sent through Realtime.
    expect(a.room!.sharedDestination!.name, '새 목적지');
    backend.failLeave = true;
    await a.leave();
    expect(a.room, isNull);
    expect(store.roomId, isNull);
    expect(store.pending, 'room1');
    final writes = backend.writes;
    clock.advance(const Duration(seconds: 10));
    fix = const LocationFix(point: GeoPoint(37.01, 127),
      accuracyMeters: 10, altitudeMeters: 0);
    signals.tick(); await flush();
    expect(backend.writes, writes);
    backend.failLeave = false;
    await a.reconnect();
    expect(store.pending, isNull);
    expect(backend.leaves, 1);
    a.dispose(); signals.dispose(); backend.dispose();
  });

  test('saved Room reloads when connection returns after startup failure', () async {
    final clock = _Clock(); final backend = _Backend(clock);
    backend.room = Room(id: 'room1', inviteCode: 'ABC234', ownerId: 'a',
      createdAt: clock.now);
    backend.members['a'] = RoomMember(userId: 'a', nickname: '환희',
      updatedAt: clock.now);
    backend.offline = true;
    final store = _Store()..nickname = '환희'..roomId = 'room1';
    final signals = _Signals();
    var connected = false;
    final a = RoomController(repository: _Repository(backend, 'a'),
      profileStore: store, locationChanges: signals,
      currentLocation: () => null, hasNetwork: () => connected,
      now: () => clock.now);
    await a.start();
    expect(a.room, isNull);
    signals.tick(); // Remember the disconnected state.
    backend.offline = false;
    connected = true;
    signals.tick();
    await flush();
    expect(a.room?.id, 'room1');
    a.dispose(); signals.dispose(); backend.dispose();
  });

  test('offline snapshot restores shared target, stale friend and valid pings', () async {
    final clock = _Clock();
    final backend = _Backend(clock)..offline = true;
    final shared = SharedDestination(point: const GeoPoint(37.54, 127.01),
      updatedBy: 'a', updatedAt: clock.now, name: '서울숲');
    final room = Room(id: 'room1', inviteCode: 'ABC234', ownerId: 'a',
      createdAt: clock.now, sharedDestination: shared);
    final cache = _SnapshotStore()..value = RoomSnapshot(room: room,
      members: [RoomMember(userId: 'a', nickname: '철수',
        point: const GeoPoint(37.55, 127.02), updatedAt: clock.now)],
      pings: [SharedPing(id: 'p1', point: const GeoPoint(37.55, 127),
        createdBy: 'a', createdByNickname: '철수', createdAt: clock.now)]);
    final store = _Store()..roomId = room.id;
    final signals = _Signals();
    var connected = false;
    final controller = RoomController(repository: _Repository(backend, 'b'),
      profileStore: store, snapshotStore: cache, locationChanges: signals,
      currentLocation: () => null, hasNetwork: () => connected,
      now: () => clock.now);
    final personal = DestinationController(locationProvider: _Location(),
      headingProvider: _Heading(), networkMonitor: _Network(),
      store: _DestinationStore());
    final nav = NavigationTargetController(personal, controller);
    await controller.start();
    expect(nav.target?.point, shared.point);
    expect(nav.target?.modeLabel, contains('마지막으로 동기화'));
    expect(controller.activePings.single.id, 'p1');
    nav.followMember('a');
    expect(nav.target?.point, const GeoPoint(37.55, 127.02));
    expect(nav.target?.notice, contains('마지막 위치 기준'));
    await expectLater(controller.sendPing(shared.point), throwsStateError);
    await expectLater(controller.setSharedDestination(shared.point, '다른 장소'),
      throwsStateError);
    clock.advance(const Duration(minutes: 31));
    expect(controller.activePings, isEmpty);
    backend.room = room;
    backend.members['a'] = cache.value!.members.single;
    backend.offline = false;
    connected = true;
    signals.tick();
    await flush();
    expect(controller.error, isNull);
    expect(nav.target?.notice, contains('오래되었습니다'));
    await controller.leave();
    expect(cache.value, isNull);
    nav.dispose(); personal.dispose(); controller.dispose();
    signals.dispose(); backend.dispose();
  });

  test('room snapshot preference cache round-trips shared coordinates', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = PreferencesRoomSnapshotStore();
    final now = DateTime.utc(2026, 9, 28);
    await cache.save(RoomSnapshot(
      room: Room(id: 'r1', inviteCode: 'ABC234', ownerId: 'a',
        createdAt: now, sharedDestination: SharedDestination(
          point: const GeoPoint(37.52, 127.1), name: '서울숲',
          updatedBy: 'a', updatedAt: now)),
      members: [RoomMember(userId: 'a', nickname: '철수',
        point: const GeoPoint(37.5, 127.2), updatedAt: now)],
      pings: [SharedPing(id: 'p1', point: const GeoPoint(37.6, 127.1),
        createdBy: 'a', createdByNickname: '철수', createdAt: now)]));
    final loaded = await cache.load();
    expect(loaded?.room.sharedDestination?.point, const GeoPoint(37.52, 127.1));
    expect(loaded?.members.single.point, const GeoPoint(37.5, 127.2));
    expect(loaded?.pings.single.id, 'p1');
    await cache.save(null);
    expect(await cache.load(), isNull);
  });
}
