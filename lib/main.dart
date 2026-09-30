import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/service_configuration.dart';
import 'core/config/service_initialization.dart';
import 'map/kakao_map_state.dart';
import 'room/realtime_room_repository.dart';
import 'room/room_repository.dart';

const kakaoNativeAppKey = String.fromEnvironment('KAKAO_NATIVE_APP_KEY');
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
const configuration = ServiceConfiguration(
  kakaoNativeAppKey: kakaoNativeAppKey,
  supabaseUrl: supabaseUrl,
  supabasePublishableKey: supabasePublishableKey,
  mapboxAccessToken: mapboxAccessToken,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final mapboxInitialization = await initializeService(
    configured: configuration.mapboxConfigured, service: 'mapbox',
    initialize: () async {
      MapboxOptions.setAccessToken(mapboxAccessToken);
    });
  final mapError = ValueNotifier<KakaoFailure?>(null);
  RoomRepository? roomRepository;
  final supabaseInitialization = await initializeService(
    configured: configuration.supabaseConfigured, service: 'supabase',
    classify: (error) => error is AuthException
        ? InitializationFailure.authentication : classifyInitializationFailure(error),
    initialize: () async {
      await Supabase.initialize(url: supabaseUrl,
        publishableKey: supabasePublishableKey);
      roomRepository = RealtimeRoomRepository(Supabase.instance.client);
    });
  runApp(DestinationCompassApp(
    mapConfigured: configuration.kakaoConfigured,
    mapError: mapError,
    roomRepository: roomRepository,
    mapboxConfigured: mapboxInitialization.state == InitializationState.initialized,
    configuration: configuration,
    supabaseInitialization: supabaseInitialization,
    mapboxInitialization: mapboxInitialization,
  ));
}
