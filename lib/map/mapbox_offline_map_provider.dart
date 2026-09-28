import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import '../core/geo_point.dart';
import '../core/location/location_provider.dart';
import '../destination/destination_model.dart';
import '../offline/offline_tile_backend.dart';
import 'map_provider.dart';

/// All Mapbox SDK annotations and map events remain inside this adapter.
class MapboxOfflineMapProvider implements MapProvider, CameraAwareMapProvider {
  mb.MapboxMap? _map;
  mb.CircleAnnotationManager? _circles;
  mb.PointAnnotationManager? _labels;
  final Map<String, mb.CircleAnnotation> _pins = {};
  final Map<String, mb.PointAnnotation> _text = {};
  final Map<String, String> _memberPinIds = {};
  void Function(String)? _onMemberTapped;
  Destination? _destination;
  GeoPoint? _candidate;
  LocationFix? _location;
  List<MapMemberOverlay> _members = const [];
  List<MapPingOverlay> _pings = const [];
  MapCameraState? _savedCamera;
  double _pinReveal = 1;
  bool _disposed = false;
  int _generation = 0;
  Future<void> _operations = Future<void>.value();

  @override
  MapCameraState? get cameraState => _savedCamera;

  static mb.Point _point(GeoPoint point) =>
      mb.Point(coordinates: mb.Position(point.longitude, point.latitude));

  @override
  Widget buildMap({required double bottomPadding,
      required ValueChanged<GeoPoint> onPicked,
      required void Function(GeoPoint, String) onNamedPlacePicked,
      required VoidCallback onLoaded, required VoidCallback onGesture,
      void Function(String memberId)? onMemberTapped}) {
    _onMemberTapped = onMemberTapped;
    final initial = _savedCamera ?? MapCameraState(
        _location?.point ?? _destination?.point ??
            const GeoPoint(37.5666, 126.979));
    return mb.MapWidget(
      styleUri: MapboxTileBackend.styleUri,
      // ignore: deprecated_member_use
      cameraOptions: mb.CameraOptions(center: _point(initial.center),
        zoom: initial.zoom, bearing: initial.bearing, pitch: initial.pitch),
      onMapCreated: (map) {
        _map = map;
        final generation = _generation;
        unawaited(_initialize(map, generation));
      },
      onMapLoadedListener: (_) => onLoaded(),
      // ignore: deprecated_member_use
      onTapListener: (context) => onPicked(GeoPoint(
        context.point.coordinates.lat.toDouble(),
        context.point.coordinates.lng.toDouble())),
      // ignore: deprecated_member_use
      onLongTapListener: (context) => onPicked(GeoPoint(
        context.point.coordinates.lat.toDouble(),
        context.point.coordinates.lng.toDouble())),
      onScrollListener: (_) => onGesture(),
      onZoomListener: (_) => onGesture(),
      onCameraChangeListener: (event) {
        final state = event.cameraState;
        _savedCamera = MapCameraState(GeoPoint(
            state.center.coordinates.lat.toDouble(),
            state.center.coordinates.lng.toDouble()),
          zoom: state.zoom, bearing: state.bearing, pitch: state.pitch);
      },
    );
  }

  Future<void> _initialize(mb.MapboxMap map, int generation) async {
    final circles = await map.annotations.createCircleAnnotationManager();
    final labels = await map.annotations.createPointAnnotationManager();
    if (_disposed || generation != _generation) return;
    _circles = circles;
    _labels = labels;
    circles.tapEvents(onTap: (annotation) {
      final id = _memberPinIds[annotation.id];
      if (id != null) _onMemberTapped?.call(id);
    });
    await _enqueue(_reconcile);
    final camera = _savedCamera;
    if (camera != null) await restoreCamera(camera);
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final generation = _generation;
    final next = _operations.then((_) async {
      if (!_disposed && generation == _generation) await action();
    });
    _operations = next.catchError((Object _) {});
    return next;
  }

  Future<void> _reconcile() async {
    final circles = _circles;
    final labels = _labels;
    if (circles == null || labels == null) return;
    final entries = <String, (GeoPoint, String, int, double)>{};
    if (_location != null) {
      entries['user'] = (_location!.point, '나', 0xFF2288E5, 1);
    }
    if (_destination != null) {
      entries['destination'] =
          (_destination!.point, _destination!.title, 0xFFEE643D, _pinReveal);
    }
    if (_candidate != null) {
      entries['candidate'] = (_candidate!, '선택한 위치', 0xFF2C67D9, 1);
    }
    for (final member in _members) {
      entries['member_${member.id}'] = (member.point, member.name,
          member.isStale ? 0xFF8796A0 : 0xFF39C2A4, 1);
    }
    for (final ping in _pings) {
      entries['ping_${ping.id}'] = (ping.point, ping.label, 0xFFF2B458, 1);
    }
    for (final id in _pins.keys.toList()) {
      if (entries.containsKey(id)) continue;
      await circles.delete(_pins.remove(id)!);
      if (_text.containsKey(id)) {
        await labels.delete(_text.remove(id)!);
      }
    }
    _memberPinIds.clear();
    for (final entry in entries.entries) {
      final id = entry.key;
      final (point, name, color, opacity) = entry.value;
      var marker = _pins[id];
      if (marker == null) {
        marker = await circles.create(mb.CircleAnnotationOptions(
          geometry: _point(point), circleRadius: id == 'user' ? 9 : 11,
          circleColor: color, circleOpacity: opacity,
          circleStrokeColor: 0xFFFFFFFF, circleStrokeWidth: 2));
        _pins[id] = marker;
        _text[id] = await labels.create(mb.PointAnnotationOptions(
          geometry: _point(point), textField: name, textColor: 0xFF18344A,
          textHaloColor: 0xFFFFFFFF, textHaloWidth: 2,
          textSize: 12, textOffset: const [0, 2]));
      } else {
        if (marker.geometry.coordinates.lng != point.longitude ||
            marker.geometry.coordinates.lat != point.latitude ||
            marker.circleColor != color || marker.circleOpacity != opacity) {
          marker.geometry = _point(point);
          marker.circleColor = color;
          marker.circleOpacity = opacity;
          await circles.update(marker);
        }
        final text = _text[id];
        if (text != null && (text.geometry.coordinates.lng != point.longitude ||
            text.geometry.coordinates.lat != point.latitude ||
            text.textField != name)) {
          text.geometry = _point(point);
          text.textField = name;
          await labels.update(text);
        }
      }
      if (id.startsWith('member_')) {
        _memberPinIds[marker.id] = id.substring('member_'.length);
      }
    }
  }

  @override
  Future<void> moveCamera(GeoPoint point, {double? zoom}) async {
    final state = _savedCamera ?? MapCameraState(point);
    await restoreCamera(MapCameraState(point, zoom: zoom ?? state.zoom,
      bearing: state.bearing, pitch: state.pitch));
  }

  @override
  Future<void> restoreCamera(MapCameraState state) async {
    _savedCamera = state;
    await _map?.setCamera(mb.CameraOptions(center: _point(state.center),
      zoom: state.zoom, bearing: state.bearing, pitch: state.pitch));
  }

  @override
  Future<void> setDestination(Destination? destination) {
    if (_destination?.point == destination?.point &&
        _destination?.name == destination?.name) {
      return Future<void>.value();
    }
    _destination = destination;
    return _enqueue(_reconcile);
  }

  @override
  void setPinReveal(double progress) {
    _pinReveal = progress.clamp(0.0, 1.0).toDouble();
    final marker = _pins['destination'];
    if (marker != null && _circles != null) {
      marker.circleOpacity = _pinReveal;
      unawaited(_enqueue(() => _circles!.update(marker)));
    }
  }

  @override
  Future<void> setCandidate(GeoPoint? candidate) {
    if (_candidate == candidate) return Future<void>.value();
    _candidate = candidate;
    return _enqueue(_reconcile);
  }

  @override
  Future<void> setUserLocation(LocationFix? location, {required bool follow}) {
    if (_location?.point == location?.point &&
        _location?.accuracyMeters == location?.accuracyMeters) {
      return Future<void>.value();
    }
    _location = location;
    return _enqueue(() async {
      await _reconcile();
      if (follow && location != null) {
        await moveCamera(location.point,
          zoom: _savedCamera == null ? 16 : null);
      }
    });
  }

  @override
  Future<void> setMembers(List<MapMemberOverlay> members) {
    _members = members;
    return _enqueue(_reconcile);
  }

  @override
  Future<void> setSharedPings(List<MapPingOverlay> pings) {
    _pings = pings;
    return _enqueue(_reconcile);
  }

  @override
  void reset() {
    _generation++;
    _map = null;
    _circles = null;
    _labels = null;
    _pins.clear();
    _text.clear();
    _memberPinIds.clear();
    _onMemberTapped = null;
    // MapWidget owns disposal of the native map on subtree removal.
  }

  @override
  void dispose() {
    _disposed = true;
    reset();
  }
}
