import 'dart:async';

import 'package:flutter/material.dart';

import '../core/geo_point.dart';
import '../core/location/location_provider.dart';
import '../destination/destination_model.dart';
import 'kakao_map_bridge.dart';
import 'kakao_map_state.dart';
import 'kakao_diagnostics.dart';
import '../core/diagnostics.dart';
import 'map_provider.dart';
import 'map_user_heading.dart';

/// Online map adapter. All native traffic is batched as stable-ID overlays.
class KakaoMapProvider implements MapProvider, CameraAwareMapProvider, UserHeadingMapProvider {
  KakaoMapProvider({required this.appKey, this.onFailure, KakaoMapBridge? bridge})
      : _bridge = bridge ?? PlatformKakaoMapBridge(),
        diagnostics = ValueNotifier(KakaoDiagnostics(
          keyPresent: appKey.trim().isNotEmpty));

  final String appKey;
  final ValueChanged<KakaoFailure>? onFailure;
  final KakaoMapBridge _bridge;
  final ValueNotifier<KakaoDiagnostics> diagnostics;

  Future<void> refreshRuntimeIdentity() async {
    try {
      final id = await _bridge.runtimeBundleIdentifier();
      if (!_disposed) diagnostics.value = diagnostics.value.withRuntimeBundleId(id);
    } catch (_) {
      diagnosticEvent('runtime.bundleIdentifier', 'unavailable');
    }
  }
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
  double? _userHeading;
  double? get displayedUserHeading => MapUserHeading.display(_userHeading, _camera?.bearing ?? 0);
  static const headingUpdateInterval = Duration(milliseconds: 50);
  Timer? _headingTimer;
  bool _headingDirty = false;
  bool _headingSending = false;
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
      if (event.containsKey('stage') || event.containsKey('runtimeBundleId')) {
        diagnostics.value = diagnostics.value.apply(event);
        final stage = diagnostics.value.stage;
        if (stage != null) diagnosticEvent('kakao.stage', stage.name);
      }
      switch (event['type']) {
        case 'attached':
          _attached = true;
          _headingDirty = true;
          _scheduleHeading();
          _queue(() => _bridge.send('padding', {'bottom': _bottomPadding}))
              .catchError((Object _) {});
          _scheduleSync();
        case 'loaded':
          if (_ready) return;
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
          final reason = switch (event['category']) {
            'authentication' => KakaoFailure.authentication,
            'addView' => KakaoFailure.addView,
            'bridge' => KakaoFailure.bridge,
            'prepareTimeout' => KakaoFailure.prepareTimeout,
            'timeout' => KakaoFailure.timeout,
            _ => KakaoFailure.initialization,
          };
          diagnosticEvent('kakao.nativeFailure', reason.name);
          onFailure?.call(reason);
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
        if (_location != null) {..._marker('user', _location!.point, '내 위치', 'user'),
          'heading': _userHeading},
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
  Future<void> setUserHeading(double? heading) async {
    if (_disposed) return;
    final normalized = MapUserHeading.display(heading, 0);
    if (normalized == _userHeading) return;
    _userHeading = normalized;
    _headingDirty = true;
    _scheduleHeading();
  }

  void _scheduleHeading() {
    if (!_attached || _disposed || _headingSending || _headingTimer != null) return;
    // Latest-wins, <=20 calls/s, one in flight. No overlay reconciliation or
    // camera movement is triggered by sensor events.
    _headingTimer = Timer(headingUpdateInterval, () => unawaited(_flushHeading()));
  }

  Future<void> _flushHeading() async {
    _headingTimer = null;
    if (_disposed || !_attached || !_headingDirty) return;
    final generation = _generation;
    _headingDirty = false;
    _headingSending = true;
    try {
      await _bridge.send('userHeading', {'heading': _userHeading});
    } catch (_) {
      diagnosticEvent('kakao.userHeading', 'bridgeFailure');
    } finally {
      if (!_disposed && generation == _generation) {
        _headingSending = false;
        if (_headingDirty) _scheduleHeading();
      }
    }
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
    _headingTimer?.cancel();
    _headingTimer = null;
    _headingSending = false;
    _headingDirty = true;
    _generation++;
    _ready = false;
    _attached = false;
    _bridge.detach();
  }

  @override
  void dispose() {
    _disposed = true;
    reset();
    diagnostics.dispose();
  }
}
