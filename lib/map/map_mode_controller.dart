import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/geo_point.dart';
import '../offline/offline_map_controller.dart';

enum MapMode { onlineNaver, offlineMapbox, mapUnavailable }

/// Connectivity is only a hint; Naver load/auth/timeout failures also count.
class MapModeController extends ChangeNotifier {
  MapModeController({required this.naverConfigured,
    required OfflineMapController offlineMaps,
    Duration switchDelay = const Duration(milliseconds: 1300),
    Duration recoveryDelay = const Duration(seconds: 3)})
      : _offlineMaps = offlineMaps, _switchDelay = switchDelay,
        _recoveryDelay = recoveryDelay {
    _offlineMaps.addListener(_reevaluate);
    mode = naverConfigured ? MapMode.onlineNaver : MapMode.mapUnavailable;
  }

  final bool naverConfigured;
  final OfflineMapController _offlineMaps;
  final Duration _switchDelay;
  final Duration _recoveryDelay;
  late MapMode mode;
  bool? connected;
  GeoPoint? currentPosition;
  bool naverFailed = false;
  Timer? _pending;
  MapMode? _pendingTarget;
  bool _disposed = false;

  void update({bool? connected, GeoPoint? position}) {
    if (connected != null && connected != this.connected) {
      if (this.connected == false && connected) naverFailed = false;
      this.connected = connected;
    }
    if (position != null) currentPosition = position;
    _reevaluate();
  }

  void naverLoaded() {
    naverFailed = false;
    _reevaluate();
  }

  void naverFailure() {
    if (naverFailed) return;
    naverFailed = true;
    _reevaluate();
  }

  void retryNaver() {
    naverFailed = false;
    _reevaluate();
  }

  MapMode get desired {
    if (naverConfigured && connected != false && !naverFailed) {
      return MapMode.onlineNaver;
    }
    if (_offlineMaps.configured &&
        _offlineMaps.covering(currentPosition) != null) {
      return MapMode.offlineMapbox;
    }
    return MapMode.mapUnavailable;
  }

  void _reevaluate() {
    if (_disposed) return;
    final next = desired;
    if (next == mode) {
      _pending?.cancel();
      _pending = null;
      _pendingTarget = null;
      return;
    }
    if (_pending?.isActive == true && _pendingTarget == next) return;
    _pending?.cancel();
    _pendingTarget = next;
    _pending = Timer(next == MapMode.onlineNaver
        ? _recoveryDelay : _switchDelay, () {
      if (_disposed) return;
      if (next != desired) {
        _reevaluate();
        return;
      }
      mode = next;
      _pendingTarget = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pending?.cancel();
    _offlineMaps.removeListener(_reevaluate);
    super.dispose();
  }
}
