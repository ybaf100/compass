import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/service_configuration.dart';
import 'room/realtime_room_repository.dart';
import 'room/room_repository.dart';

const naverClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
const configuration = ServiceConfiguration(
  naverClientId: naverClientId,
  supabaseUrl: supabaseUrl,
  supabasePublishableKey: supabasePublishableKey,
  mapboxAccessToken: mapboxAccessToken,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var mapboxReady = configuration.mapboxConfigured;
  if (configuration.mapboxConfigured) {
    try {
      MapboxOptions.setAccessToken(mapboxAccessToken);
    } catch (_) {
      mapboxReady = false;
    }
  }
  final mapError = ValueNotifier<String?>(null);
  if (configuration.naverConfigured) {
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
  if (configuration.supabaseConfigured) {
    try {
      await Supabase.initialize(url: supabaseUrl,
        publishableKey: supabasePublishableKey);
      roomRepository = RealtimeRoomRepository(Supabase.instance.client);
    } catch (_) {
      // A backend initialization error does not block personal navigation.
    }
  }
  runApp(DestinationCompassApp(
    mapConfigured: configuration.naverConfigured,
    mapError: mapError,
    roomRepository: roomRepository,
    mapboxConfigured: mapboxReady,
    configuration: configuration,
  ));
}
