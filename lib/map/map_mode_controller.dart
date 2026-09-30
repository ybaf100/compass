import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/geo_point.dart';
import '../core/network/network_monitor.dart';
import '../core/diagnostics.dart';
import '../offline/offline_map_controller.dart';
import 'kakao_map_state.dart';

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
    kakaoState = kakaoConfigured ? KakaoState.initializing : KakaoState.notConfigured;
  }

  final bool kakaoConfigured;
  final OfflineMapController _offlineMaps;
  final Duration _switchDelay;
  final Duration _recoveryDelay;
  late MapMode mode;
  NetworkState networkState = NetworkState.unknown;
  GeoPoint? currentPosition;
  late KakaoState kakaoState;
  KakaoFailure? failure;
  bool get kakaoFailed => failure != null;
  // Native owns the bounded 499 retry budget. Terminal authentication failures
  // require an explicit user retry, never a resume/connectivity retry loop.
  bool get canRetryAutomatically => failure != KakaoFailure.authentication;
  int attempt = 0;
  Timer? _pending;
  MapMode? _pendingTarget;
  bool _disposed = false;

  void update({NetworkState? networkState, GeoPoint? position}) {
    var recovering = false;
    if (networkState != null && networkState != this.networkState) {
      recovering = networkState == NetworkState.available && kakaoFailed && canRetryAutomatically;
      this.networkState = networkState;
    }
    if (position != null) currentPosition = position;
    if (recovering) {
      retryKakao();
    } else {
      _reevaluate();
    }
  }

  void kakaoLoaded() {
    failure = null;
    kakaoState = KakaoState.loaded;
    diagnosticEvent('kakao', 'loaded');
    _reevaluate();
    if (!_disposed) notifyListeners();
  }

  void kakaoFailure([KakaoFailure reason = KakaoFailure.initialization]) {
    if (_disposed || failure == reason) return;
    failure = reason;
    kakaoState = reason == KakaoFailure.timeout ? KakaoState.timedOut : KakaoState.failed;
    diagnosticEvent('kakao.failure', reason.name);
    _reevaluate();
    notifyListeners();
  }

  void retryKakao() {
    if (_disposed || !kakaoConfigured || networkState == NetworkState.unavailable) return;
    failure = null;
    kakaoState = KakaoState.initializing;
    attempt++;
    diagnosticEvent('kakao', 'retry');
    _reevaluate();
    notifyListeners();
  }

  MapMode get desired {
    if (kakaoConfigured && networkState != NetworkState.unavailable && !kakaoFailed) {
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
