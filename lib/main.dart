import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'room/realtime_room_repository.dart';
import 'room/room_repository.dart';

const naverClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

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
  RoomRepository? roomRepository;
  if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) {
    try {
      await Supabase.initialize(url: supabaseUrl,
        anonKey: supabasePublishableKey);
      roomRepository = RealtimeRoomRepository(Supabase.instance.client);
    } catch (_) {
      // A backend initialization error does not block personal navigation.
    }
  }
  runApp(DestinationCompassApp(
    mapConfigured: naverClientId.isNotEmpty,
    mapError: mapError,
    roomRepository: roomRepository,
  ));
}
