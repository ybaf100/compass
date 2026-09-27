import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import 'app.dart';

const naverClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final mapError = ValueNotifier<String?>(null);
  if (naverClientId.isNotEmpty) {
    try {
      await FlutterNaverMap().init(
        clientId: naverClientId,
        onAuthFailed: (error) {
          mapError.value = '네이버 지도 인증에 실패했습니다. Client ID와 앱 등록 정보를 확인하세요.';
        },
      );
    } catch (_) {
      mapError.value = '네이버 지도 초기화에 실패했습니다.';
    }
  }
  runApp(DestinationCompassApp(
    mapConfigured: naverClientId.isNotEmpty,
    mapError: mapError,
  ));
}
