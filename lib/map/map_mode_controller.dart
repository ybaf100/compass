import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/geo_point.dart';
import '../offline/offline_map_controller.dart';

enum MapMode { onlineKakao, offlineMapbox, mapUnavailable }

/// Connectivity is only a hint; Kakao load/auth/timeout failures also count.
class MapModeController extends ChangeNotifier {
  MapModeController({required this.kakaoConfigured,
    required OfflineMapController offlineMaps,
    Duration switchDelay = const Duration(milliseconds: 1300),
    Duration recoveryDelay = const Duration(seconds: 3)})
      : _offlineMaps = offlineMaps, _switchDelay = switchDelay,
        _recoveryDelay = recoveryDelay {
    _offlineMaps.addListener(_reevaluate);
    mode = kakaoConfigured ? MapMode.onlineKakao : MapMode.mapUnavailable;
  }

  final bool kakaoConfigured;
  final OfflineMapController _offlineMaps;
  final Duration _switchDelay;
  final Duration _recoveryDelay;
  late MapMode mode;
  bool? connected;
  GeoPoint? currentPosition;
  bool kakaoFailed = false;
  Timer? _pending;
  MapMode? _pendingTarget;
  bool _disposed = false;

  void update({bool? connected, GeoPoint? position}) {
    if (connected != null && connected != this.connected) {
      if (this.connected == false && connected) kakaoFailed = false;
      this.connected = connected;
    }
    if (position != null) currentPosition = position;
    _reevaluate();
  }

  void kakaoLoaded() {
    kakaoFailed = false;
    _reevaluate();
  }

  void kakaoFailure() {
    if (kakaoFailed) return;
    kakaoFailed = true;
    _reevaluate();
  }

  void retryKakao() {
    kakaoFailed = false;
    _reevaluate();
  }

  MapMode get desired {
    if (kakaoConfigured && connected != false && !kakaoFailed) {
      return MapMode.onlineKakao;
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
    _pending = Timer(next == MapMode.onlineKakao
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
