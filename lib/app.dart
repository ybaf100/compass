import 'dart:async';

import 'package:flutter/material.dart';

import 'core/compass/native_heading_provider.dart';
import 'core/location/geolocator_location_provider.dart';
import 'core/network/network_monitor.dart';
import 'destination/destination_controller.dart';
import 'destination/destination_store.dart';
import 'map/naver_map_provider.dart';
import 'map/mapbox_offline_map_provider.dart';
import 'map/map_mode_controller.dart';
import 'offline/offline_map_controller.dart';
import 'offline/offline_region_repository.dart';
import 'offline/offline_tile_backend.dart';
import 'navigation/navigation_target.dart';
import 'room/profile_store.dart';
import 'room/room_controller.dart';
import 'room/room_repository.dart';
import 'room/room_snapshot_store.dart';
import 'ui/map_screen.dart';

class DestinationCompassApp extends StatefulWidget {
  const DestinationCompassApp({
    super.key,
    required this.mapConfigured,
    required this.mapError,
    required this.roomRepository,
    required this.mapboxConfigured,
  });

  final bool mapConfigured;
  final ValueNotifier<String?> mapError;
  final RoomRepository? roomRepository;
  final bool mapboxConfigured;

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
  late final MapboxOfflineMapProvider? _offlineProvider =
      widget.mapboxConfigured ? MapboxOfflineMapProvider() : null;
  late final OfflineMapController _offlineMaps = OfflineMapController(
    repository: PreferencesOfflineRegionRepository(),
    backend: widget.mapboxConfigured ? MapboxTileBackend() : null);
  late final MapModeController _mapMode = MapModeController(
    naverConfigured: widget.mapConfigured, offlineMaps: _offlineMaps);
  late final RoomController _roomController = RoomController(
    repository: widget.roomRepository,
    profileStore: PreferencesProfileStore(),
    locationChanges: _controller,
    currentLocation: () => _controller.location,
    hasNetwork: () => _controller.hasNetwork,
    snapshotStore: PreferencesRoomSnapshotStore(),
  );
  late final NavigationTargetController _navigation =
      NavigationTargetController(_controller, _roomController);

  @override
  void initState() {
    super.initState();
    _mapMode.addListener(_onModeChanged);
  }

  void _onModeChanged() {
    unawaited(_offlineMaps.setMapboxConnected(
      _mapMode.mode != MapMode.offlineMapbox));
  }

  @override
  void dispose() {
    _navigation.dispose();
    _mapMode.removeListener(_onModeChanged);
    _mapMode.dispose();
    unawaited(_offlineMaps.setMapboxConnected(true));
    _offlineMaps.dispose();
    _roomController.dispose();
    _controller.dispose();
    _mapProvider.dispose();
    _offlineProvider?.dispose();
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
      offlineMapProvider: _offlineProvider,
      offlineMaps: _offlineMaps,
      mapMode: _mapMode,
    ),
  );
}
