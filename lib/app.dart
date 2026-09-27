import 'package:flutter/material.dart';

import 'core/compass/native_heading_provider.dart';
import 'core/location/geolocator_location_provider.dart';
import 'core/network/network_monitor.dart';
import 'destination/destination_controller.dart';
import 'destination/destination_store.dart';
import 'map/naver_map_provider.dart';
import 'navigation/navigation_target.dart';
import 'room/profile_store.dart';
import 'room/room_controller.dart';
import 'room/room_repository.dart';
import 'ui/map_screen.dart';

class DestinationCompassApp extends StatefulWidget {
  const DestinationCompassApp({
    super.key,
    required this.mapConfigured,
    required this.mapError,
    required this.roomRepository,
  });

  final bool mapConfigured;
  final ValueNotifier<String?> mapError;
  final RoomRepository? roomRepository;

  @override
  State<DestinationCompassApp> createState() => _DestinationCompassAppState();
}

class _DestinationCompassAppState extends State<DestinationCompassApp> {
  late final DestinationController _controller = DestinationController(
    locationProvider: GeolocatorLocationProvider(),
    headingProvider: NativeHeadingProvider(),
    networkMonitor: ConnectivityNetworkMonitor(),
    store: PreferencesDestinationStore(),
  );
  late final NaverMapProvider _mapProvider = NaverMapProvider();
  late final RoomController _roomController = RoomController(
    repository: widget.roomRepository,
    profileStore: PreferencesProfileStore(),
    locationChanges: _controller,
    currentLocation: () => _controller.location,
    hasNetwork: () => _controller.hasNetwork,
  );
  late final NavigationTargetController _navigation =
      NavigationTargetController(_controller, _roomController);

  @override
  void dispose() {
    _navigation.dispose();
    _roomController.dispose();
    _controller.dispose();
    _mapProvider.dispose();
    widget.mapError.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '목적지 나침반',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2CB8D3)),
      scaffoldBackgroundColor: const Color(0xFF081827),
    ),
    home: MapScreen(
      controller: _controller,
      mapProvider: _mapProvider,
      mapConfigured: widget.mapConfigured,
      mapError: widget.mapError,
      roomController: _roomController,
      navigationController: _navigation,
    ),
  );
}
