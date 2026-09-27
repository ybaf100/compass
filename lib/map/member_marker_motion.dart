import 'package:flutter/animation.dart';

import '../core/geo_point.dart';
import '../destination/bearing_engine.dart';
import 'map_provider.dart';

/// Drives short marker moves on the display ticker, never with a fixed timer.
class MemberMarkerMotion {
  MemberMarkerMotion({required TickerProvider vsync,
      required void Function(List<MapMemberOverlay>) onFrame})
      : _onFrame = onFrame {
    _animation = AnimationController(vsync: vsync,
      duration: const Duration(milliseconds: 360))
      ..addListener(_render);
  }

  final void Function(List<MapMemberOverlay>) _onFrame;
  late final AnimationController _animation;
  List<MapMemberOverlay> _rendered = const [];
  List<MapMemberOverlay> _target = const [];
  Map<String, GeoPoint> _from = const {};

  void update(List<MapMemberOverlay> next) {
    final previous = {for (final m in _target) m.id: m};
    if (next.length == _target.length && next.every((m) {
      final old = previous[m.id];
      return old != null && old.point == m.point &&
          old.name == m.name && old.isStale == m.isStale;
    })) {
      return;
    }
    final current = {for (final m in _rendered) m.id: m};
    final now = DateTime.now().toUtc();
    _from = {for (final member in next)
      member.id: _startPoint(current[member.id], member, now)};
    _target = next;
    _animation.forward(from: 0);
    _render();
  }

  static GeoPoint _startPoint(MapMemberOverlay? old,
      MapMemberOverlay current, DateTime now) {
    if (old == null || old.isStale || current.isStale ||
        now.difference(old.updatedAt) > const Duration(seconds: 45) ||
        BearingEngine.distanceMeters(old.point, current.point) > 150) {
      return current.point;
    }
    return old.point;
  }

  void _render() {
    final progress = Curves.easeOutCubic.transform(_animation.value);
    _rendered = [for (final member in _target)
      member.at(GeoPoint(
        _from[member.id]!.latitude +
          (member.point.latitude - _from[member.id]!.latitude) * progress,
        _from[member.id]!.longitude +
          (member.point.longitude - _from[member.id]!.longitude) * progress,
      ))];
    _onFrame(_rendered);
  }

  void dispose() => _animation.dispose();
}
