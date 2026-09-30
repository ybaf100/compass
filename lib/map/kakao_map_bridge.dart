import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Wire protocol shared by the Android/iOS platform views. SDK objects never
/// cross this boundary; a fake bridge can exercise the entire provider.
abstract class KakaoMapBridge {
  Widget build({required String appKey, required ValueChanged<Map<String, dynamic>> onEvent});
  Future<void> send(String method, Map<String, dynamic> arguments);
  void detach();
}

class PlatformKakaoMapBridge implements KakaoMapBridge {
  MethodChannel? _channel;
  ValueChanged<Map<String, dynamic>>? _onEvent;

  @override
  Widget build({required String appKey,
    required ValueChanged<Map<String, dynamic>> onEvent}) {
    _onEvent = onEvent;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return const SizedBox.shrink();
    }
    const viewType = 'app.destination_compass/kakao_map';
    final params = <String, dynamic>{'appKey': appKey};
    if (Platform.isAndroid) {
      return AndroidView(viewType: viewType, creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _attach);
    }
    return UiKitView(viewType: viewType, creationParams: params,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _attach);
  }

  void _attach(int id) {
    final channel = MethodChannel('app.destination_compass/kakao_map_$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      final raw = call.arguments;
      if (call.method == 'event' && raw is Map) {
        _onEvent?.call(Map<String, dynamic>.from(raw));
      }
    });
    _onEvent?.call({'type': 'attached'});
    // Native authentication can finish before Flutter attaches its handler.
    channel.invokeMapMethod<String, dynamic>('status').then((status) {
      if (_channel == channel && status != null &&
          (status['type'] == 'loaded' || status['type'] == 'failed')) {
        _onEvent?.call(status);
      }
    }).catchError((Object _) {
      if (_channel == channel) _onEvent?.call({'type': 'failed', 'category': 'bridge'});
    });
  }

  @override
  Future<void> send(String method, Map<String, dynamic> arguments) async {
    final channel = _channel;
    if (channel != null) await channel.invokeMethod<void>(method, arguments);
  }

  @override
  void detach() {
    _channel?.setMethodCallHandler(null);
    _channel = null;
    _onEvent = null;
  }
}
