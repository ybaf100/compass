import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/service_configuration.dart';
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
  var mapboxReady = configuration.mapboxConfigured;
  if (configuration.mapboxConfigured) {
    try {
      MapboxOptions.setAccessToken(mapboxAccessToken);
    } catch (_) {
      mapboxReady = false;
    }
  }
  final mapError = ValueNotifier<String?>(null);
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
    mapConfigured: configuration.kakaoConfigured,
    mapError: mapError,
    roomRepository: roomRepository,
    mapboxConfigured: mapboxReady,
    configuration: configuration,
  ));
}
