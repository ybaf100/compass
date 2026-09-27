import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import '../core/geo_point.dart';
import '../core/location/location_provider.dart';
import '../destination/destination_model.dart';
import 'map_provider.dart';

/// The only app module aware of flutter_naver_map native overlay APIs.
class NaverMapProvider implements MapProvider {
  NaverMapController? _controller;
  NMarker? _destinationMarker;
  NMarker? _candidateMarker;
  Destination? _destination;
  GeoPoint? _candidate;
  LocationFix? _location;
  GeoPoint? _lastCameraPoint;
  double _pinReveal = 1.0;
  bool _disposed = false;
  Future<void> _operations = Future<void>.value();

  static const _defaultCenter = NLatLng(37.5666, 126.979);

  @override
  Widget buildMap({
    required double bottomPadding,
    required ValueChanged<GeoPoint> onPicked,
    required void Function(GeoPoint, String) onNamedPlacePicked,
    required VoidCallback onLoaded,
    required VoidCallback onGesture,
  }) => NaverMap(
    options: NaverMapViewOptions(
      initialCameraPosition: const NCameraPosition(
        target: _defaultCenter,
        zoom: 14,
      ),
      contentPadding: EdgeInsets.only(bottom: bottomPadding),
      scaleBarEnable: true,
      locationButtonEnable: false,
    ),
    onMapReady: (controller) {
      _controller = controller;
      _destinationMarker = null;
      _candidateMarker = null;
      _lastCameraPoint = null;
      _queue(_reconcile).catchError((Object _) {});
      if (_location != null) {
        _queue(() => moveCamera(_location!.point, zoom: 16))
            .catchError((Object _) {});
      } else if (_destination != null) {
        _queue(() => moveCamera(_destination!.point, zoom: 14))
            .catchError((Object _) {});
      }
    },
    onMapLoaded: onLoaded,
    onMapTapped: (_, point) => onPicked(
      GeoPoint(point.latitude, point.longitude),
    ),
    onMapLongTapped: (_, point) => onPicked(
      GeoPoint(point.latitude, point.longitude),
    ),
    onSymbolTapped: (symbol) => onNamedPlacePicked(
      GeoPoint(symbol.position.latitude, symbol.position.longitude),
      symbol.caption,
    ),
    onCameraChange: (reason, _) {
      if (reason == NCameraUpdateReason.gesture ||
          reason == NCameraUpdateReason.control) {
        onGesture();
      }
    },
  );

  Future<void> _queue(Future<void> Function() action) {
    final next = _operations.then((_) async {
      if (!_disposed) await action();
    });
    _operations = next.catchError((Object _) {});
    return next;
  }

  Future<void> _reconcile() async {
    final controller = _controller;
    if (controller == null || _disposed) return;
    final position = _location;
    final locationOverlay = controller.getLocationOverlay();
    if (position == null) {
      locationOverlay.setIsVisible(false);
    } else {
      locationOverlay.setPosition(_latLng(position.point));
      final metersPerDp = controller.getMeterPerDp();
      if (metersPerDp.isFinite && metersPerDp > 0) {
        locationOverlay.setCircleRadius(
          (position.accuracyMeters / metersPerDp).clamp(12.0, 100.0).toDouble(),
        );
      }
      locationOverlay.setIsVisible(true);
    }

    final destination = _destination;
    if (destination == null && _destinationMarker != null) {
      await controller.deleteOverlay(_destinationMarker!.info);
      _destinationMarker = null;
    } else if (destination != null) {
      if (_destinationMarker == null) {
        final marker = NMarker(
          id: 'destination',
          position: _latLng(destination.point),
          caption: const NOverlayCaption(text: '목적지'),
          iconTintColor: const Color(0xFFEE643D),
          alpha: _pinReveal,
        );
        await controller.addOverlay(marker);
        _destinationMarker = marker;
      } else {
        _destinationMarker!.setPosition(_latLng(destination.point));
        _destinationMarker!.setAlpha(_pinReveal);
      }
    }

    final candidate = _candidate;
    if (candidate == null && _candidateMarker != null) {
      await controller.deleteOverlay(_candidateMarker!.info);
      _candidateMarker = null;
    } else if (candidate != null) {
      if (_candidateMarker == null) {
        final marker = NMarker(
          id: 'candidate',
          position: _latLng(candidate),
          caption: const NOverlayCaption(text: '선택한 위치'),
          iconTintColor: const Color(0xFF2C67D9),
        );
        await controller.addOverlay(marker);
        _candidateMarker = marker;
      } else {
        _candidateMarker!.setPosition(_latLng(candidate));
      }
    }
  }

  @override
  Future<void> moveCamera(GeoPoint point, {double? zoom}) async {
    final controller = _controller;
    if (controller == null || _disposed) return;
    final update = NCameraUpdate.scrollAndZoomTo(
      target: _latLng(point),
      zoom: zoom,
    );
    update.setAnimation(duration: const Duration(milliseconds: 420));
    await controller.updateCamera(update);
    _lastCameraPoint = point;
  }

  @override
  Future<void> setDestination(Destination? destination) {
    if (_destination?.point == destination?.point &&
        _destination?.name == destination?.name) {
      return Future<void>.value();
    }
    _destination = destination;
    return _queue(_reconcile);
  }

  @override
  void setPinReveal(double progress) {
    _pinReveal = progress.clamp(0.0, 1.0).toDouble();
    _destinationMarker?.setAlpha(_pinReveal);
  }

  @override
  Future<void> setCandidate(GeoPoint? candidate) {
    if (_candidate == candidate) return Future<void>.value();
    _candidate = candidate;
    return _queue(_reconcile);
  }

  @override
  Future<void> setUserLocation(LocationFix? location, {required bool follow}) {
    if (_location?.point == location?.point &&
        _location?.accuracyMeters == location?.accuracyMeters) {
      return Future<void>.value();
    }
    _location = location;
    return _queue(() async {
      await _reconcile();
      if (follow && location != null &&
          (_lastCameraPoint == null || _lastCameraPoint != location.point)) {
        await moveCamera(location.point, zoom: _lastCameraPoint == null ? 16 : null);
      }
    });
  }

  static NLatLng _latLng(GeoPoint point) =>
      NLatLng(point.latitude, point.longitude);

  @override
  void reset() {
    _controller = null;
    _destinationMarker = null;
    _candidateMarker = null;
    _lastCameraPoint = null;
  }

  @override
  void dispose() {
    _disposed = true;
    reset();
    // NaverMap's StatefulWidget owns and disposes the native controller.
  }
}
