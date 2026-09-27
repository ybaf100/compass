import 'package:flutter/foundation.dart';

import '../core/geo_point.dart';
import '../destination/bearing_engine.dart';
import '../destination/destination_controller.dart';
import '../destination/destination_model.dart';
import '../room/room_controller.dart';

enum TargetMode { personal, shared, member }

class NavigationTarget {
  const NavigationTarget({required this.mode, required this.title,
    required this.modeLabel, this.point, this.notice, this.memberId});
  final TargetMode mode;
  final GeoPoint? point;
  final String title;
  final String modeLabel;
  final String? notice;
  final String? memberId;

  Destination? get asDestination => point == null ? null : Destination(
    point: point!, name: title, createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// Chooses a target point without changing the personal destination model.
class NavigationTargetController extends ChangeNotifier {
  NavigationTargetController(this._personal, this._room) {
    _personal.addListener(_changed);
    _room.addListener(_roomChanged);
  }

  final DestinationController _personal;
  final RoomController _room;
  TargetMode mode = TargetMode.personal;
  String? targetMemberId;
  String? _lastMemberName;
  String? _roomId;
  DateTime? _sharedRevision;

  NavigationTarget? get target {
    if (mode == TargetMode.shared && _room.room != null) {
      final shared = _room.room!.sharedDestination;
      return NavigationTarget(
        mode: mode, title: shared?.title ?? '모두의 목적지가 없습니다',
        modeLabel: '모두의 목적지', point: shared?.point,
      );
    }
    if (mode == TargetMode.member && _room.room != null) {
      final member = _room.member(targetMemberId ?? '');
      final name = member?.nickname ?? _lastMemberName ?? '친구';
      final stale = member == null || member.isStale(
          _room.currentTime, RoomController.staleAfter);
      return NavigationTarget(
        mode: mode, title: name, modeLabel: '친구 따라가기',
        point: member?.point, memberId: targetMemberId,
        notice: member == null ? '$name님이 방을 나갔습니다.'
            : member.point == null ? '$name님의 위치가 없습니다.'
            : stale ? '$name님의 위치가 오래되었습니다. 마지막 업데이트: '
                '${_age(_room.currentTime.difference(member.updatedAt))} 전' : null,
      );
    }
    final personal = _personal.destination;
    if (personal == null) return null;
    return NavigationTarget(mode: TargetMode.personal,
      title: personal.title, modeLabel: '내 목적지', point: personal.point);
  }

  double? get distanceMeters => _personal.location?.point != null &&
          target?.point != null
      ? BearingEngine.distanceMeters(_personal.location!.point, target!.point!)
      : null;

  double? get bearing => _personal.location?.point != null &&
          target?.point != null
      ? BearingEngine.bearing(_personal.location!.point, target!.point!)
      : null;

  void selectPersonal() {
    mode = TargetMode.personal;
    targetMemberId = null;
    notifyListeners();
  }

  void selectShared() {
    if (_room.room == null) return;
    mode = TargetMode.shared;
    targetMemberId = null;
    notifyListeners();
  }

  void followMember(String id) {
    final member = _room.member(id);
    if (_room.room == null || member == null || id == _room.userId) return;
    mode = TargetMode.member;
    targetMemberId = id;
    _lastMemberName = member.nickname;
    notifyListeners();
  }

  void _roomChanged() {
    final current = _room.room;
    if (current?.id != _roomId) {
      _roomId = current?.id;
      _sharedRevision = current?.sharedDestination?.updatedAt;
      mode = current?.sharedDestination == null
          ? TargetMode.personal : TargetMode.shared;
      targetMemberId = null;
    } else {
      final revision = current?.sharedDestination?.updatedAt;
      if (revision != null && revision != _sharedRevision) {
        _sharedRevision = revision;
        mode = TargetMode.shared;
        targetMemberId = null;
      }
    }
    notifyListeners();
  }

  void _changed() => notifyListeners();

  static String _age(Duration duration) {
    if (duration.inMinutes > 0) return '${duration.inMinutes}분';
    return '${duration.inSeconds.clamp(0, 59)}초';
  }

  @override
  void dispose() {
    _personal.removeListener(_changed);
    _room.removeListener(_roomChanged);
    super.dispose();
  }
}
