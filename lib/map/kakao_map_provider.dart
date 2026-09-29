import 'package:flutter/material.dart';

import '../core/geo_point.dart';
import '../core/location/location_provider.dart';
import '../destination/destination_model.dart';
import 'kakao_map_bridge.dart';
import 'map_provider.dart';

/// Online map adapter. All native traffic is batched as stable-ID overlays.
class KakaoMapProvider implements MapProvider, CameraAwareMapProvider {
  KakaoMapProvider({required this.appKey, this.onFailure, KakaoMapBridge? bridge})
      : _bridge = bridge ?? PlatformKakaoMapBridge();

  final String appKey;
  final ValueChanged<String>? onFailure;
  final KakaoMapBridge _bridge;
  Destination? _destination;
  GeoPoint? _candidate;
  LocationFix? _location;
  List<MapMemberOverlay> _members = const [];
  List<MapPingOverlay> _pings = const [];
  MapCameraState? _camera;
  @override
  MapCameraState? get cameraState => _camera;
  bool _ready = false;
  bool _attached = false;
  bool _disposed = false;
  bool _follow = true;
  double _pinReveal = 1;
  double _bottomPadding = 0;
  int _generation = 0;
  Future<void> _operations = Future<void>.value();
  ValueChanged<GeoPoint>? _picked;
  VoidCallback? _loaded;
  VoidCallback? _gesture;
  void Function(String)? _memberTapped;

  @override
  Widget buildMap({required double bottomPadding,
    required ValueChanged<GeoPoint> onPicked,
    required void Function(GeoPoint, String) onNamedPlacePicked,
    required VoidCallback onLoaded, required VoidCallback onGesture,
    void Function(String memberId)? onMemberTapped}) {
    _picked = onPicked;
    _loaded = onLoaded;
    _gesture = onGesture;
    _memberTapped = onMemberTapped;
    if (_bottomPadding != bottomPadding) {
      _bottomPadding = bottomPadding;
      _queue(() async {
        if (_attached) await _bridge.send('padding', {'bottom': _bottomPadding});
      }).catchError((Object _) {});
    }
    final generation = _generation;
    return _bridge.build(appKey: appKey, onEvent: (event) {
      if (_disposed || generation != _generation) return;
      switch (event['type']) {
        case 'attached':
          _attached = true;
          _queue(() => _bridge.send('padding', {'bottom': _bottomPadding}))
              .catchError((Object _) {});
          _scheduleSync();
        case 'loaded':
          _ready = true;
          _queue(() async {
            if (_camera != null) {
              await _bridge.send('camera', _cameraPayload(_camera!));
            }
            await _sync();
          }).catchError((Object _) {});
          _loaded?.call();
        case 'failed':
          _ready = false;
          onFailure?.call('카카오 지도 인증 또는 초기화에 실패했습니다. Native app key와 플랫폼 등록을 확인하세요.');
        case 'tap':
          final point = _point(event);
          if (point != null) _picked?.call(point);
        case 'memberTap':
          final id = event['id'];
          if (id is String) _memberTapped?.call(id);
        case 'gesture':
          _gesture?.call();
        case 'camera':
          final point = _point(event);
          final zoom = event['zoom'];
          if (point != null && zoom is num) {
            _camera = MapCameraState(point, zoom: zoom.toDouble(),
              bearing: (event['bearing'] as num?)?.toDouble() ?? 0,
              pitch: (event['pitch'] as num?)?.toDouble() ?? 0);
          }
      }
    });
  }

  static GeoPoint? _point(Map<String, dynamic> event) {
    final lat = event['latitude'];
    final lon = event['longitude'];
    return lat is num && lon is num ? GeoPoint(lat.toDouble(), lon.toDouble()) : null;
  }

  Future<void> _queue(Future<void> Function() action) {
    final generation = _generation;
    final next = _operations.then((_) async {
      if (!_disposed && generation == _generation) await action();
    });
    _operations = next.catchError((Object _) {});
    return next;
  }

  void _scheduleSync() {
    _queue(_sync).catchError((Object _) {});
  }

  Future<void> _sync() async {
    if (!_attached) return;
    await _bridge.send('overlays', {
      'markers': [
        if (_location != null) _marker('user', _location!.point, '내 위치', 'user'),
        if (_candidate != null) _marker('candidate', _candidate!, '선택한 위치', 'candidate'),
        if (_destination != null && _pinReveal > 0.05)
          _marker('destination', _destination!.point,
            _destination!.name ?? '목적지', 'destination'),
        for (final member in _members) _marker('member:${member.id}', member.point,
          member.name, member.isStale ? 'stale' : 'member'),
        for (final ping in _pings) _marker('ping:${ping.id}', ping.point, ping.label, 'ping'),
      ],
    });
  }

  static Map<String, dynamic> _marker(String id, GeoPoint point,
    String label, String kind) => {
    'id': id, 'latitude': point.latitude, 'longitude': point.longitude,
    'label': label, 'kind': kind,
  };

  static Map<String, dynamic> _cameraPayload(MapCameraState state) => {
    'latitude': state.center.latitude, 'longitude': state.center.longitude,
    // Both v2 SDKs increase detail as the integer level increases. Mapbox
    // uses fractional Web-Mercator zoom; preserve approximate scale by rounding.
    'zoom': state.zoom.round().clamp(1, 21),
    'bearing': state.bearing, 'pitch': state.pitch,
  };

  @override
  Future<void> moveCamera(GeoPoint point, {double? zoom}) {
    final previous = _camera;
    _camera = MapCameraState(point, zoom: zoom ?? previous?.zoom ?? 14,
      bearing: previous?.bearing ?? 0, pitch: previous?.pitch ?? 0);
    return _queue(() async {
      if (_ready) await _bridge.send('camera', _cameraPayload(_camera!));
    });
  }

  @override
  Future<void> restoreCamera(MapCameraState state) {
    _camera = state;
    return _queue(() async {
      if (_ready) await _bridge.send('camera', _cameraPayload(state));
    });
  }

  @override
  Future<void> setDestination(Destination? destination) {
    _destination = destination;
    return _queue(_sync);
  }

  @override
  void setPinReveal(double progress) {
    final visible = progress > 0.05;
    if ((_pinReveal > 0.05) == visible) return;
    _pinReveal = progress;
    _scheduleSync();
  }

  @override
  Future<void> setCandidate(GeoPoint? candidate) {
    _candidate = candidate;
    return _queue(_sync);
  }

  @override
  Future<void> setUserLocation(LocationFix? location, {required bool follow}) {
    final previous = _location?.point;
    _location = location;
    _follow = follow;
    return _queue(() async {
      await _sync();
      if (_follow && location != null && previous != location.point) {
        _camera = MapCameraState(location.point, zoom: _camera?.zoom ?? 16,
          bearing: _camera?.bearing ?? 0, pitch: _camera?.pitch ?? 0);
        if (_ready) await _bridge.send('camera', _cameraPayload(_camera!));
      }
    });
  }

  @override
  Future<void> setMembers(List<MapMemberOverlay> members) {
    _members = members;
    return _queue(_sync);
  }

  @override
  Future<void> setSharedPings(List<MapPingOverlay> pings) {
    _pings = pings;
    return _queue(_sync);
  }

  @override
  void reset() {
    _generation++;
    _ready = false;
    _attached = false;
    _bridge.detach();
  }

  @override
  void dispose() {
    _disposed = true;
    reset();
  }
}
