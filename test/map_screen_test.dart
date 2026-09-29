import 'package:destination_compass/core/compass/heading_provider.dart';
import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/core/config/service_configuration.dart';
import 'package:destination_compass/core/location/location_provider.dart';
import 'package:destination_compass/core/network/network_monitor.dart';
import 'package:destination_compass/destination/destination_controller.dart';
import 'package:destination_compass/destination/destination_model.dart';
import 'package:destination_compass/destination/destination_store.dart';
import 'package:destination_compass/map/map_provider.dart';
import 'package:destination_compass/map/map_mode_controller.dart';
import 'package:destination_compass/offline/offline_map_controller.dart';
import 'package:destination_compass/offline/offline_region.dart';
import 'package:destination_compass/offline/offline_region_repository.dart';
import 'package:destination_compass/offline/offline_tile_backend.dart';
import 'package:destination_compass/ui/compass_panel.dart';
import 'package:destination_compass/ui/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Location implements LocationProvider {
  @override
  Future<LocationAccess> checkAccess({required bool requestPermission}) async =>
      LocationAccess.denied;
  @override
  Stream<LocationFix> get positions => const Stream.empty();
  @override
  Stream<bool> get serviceEnabled => const Stream.empty();
  @override
  Future<void> openAppSettings() async {}
  @override
  Future<void> openLocationSettings() async {}
}

class _Heading implements HeadingProvider {
  @override
  Stream<HeadingReading?> get heading => const Stream.empty();
  @override
  Future<void> updateLocation(double latitude, double longitude, double altitude) async {}
}

class _Network implements NetworkMonitor {
  @override
  Future<bool> get hasConnection async => true;
  @override
  Stream<bool> get changes => const Stream.empty();
}

class _Store implements DestinationStore {
  Destination? value;
  @override
  Future<Destination?> load() async => value;
  @override
  Future<void> save(Destination? destination) async {
    value = destination;
  }
}

class _Map implements MapProvider, CameraAwareMapProvider {
  MapCameraState? state;
  Destination? destination;
  GeoPoint? candidate;
  bool loaded = false;
  @override
  MapCameraState? get cameraState => state;
  @override
  Future<void> restoreCamera(MapCameraState camera) async { state = camera; }
  @override
  Widget buildMap({required double bottomPadding,
    required ValueChanged<GeoPoint> onPicked,
    required void Function(GeoPoint, String) onNamedPlacePicked,
    required VoidCallback onLoaded,
    required VoidCallback onGesture,
    void Function(String memberId)? onMemberTapped,
  }) {
    if (!loaded) {
      loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => onLoaded());
    }
    return const ColoredBox(color: Colors.blue);
  }
  @override
  Future<void> moveCamera(GeoPoint point, {double? zoom}) async {
    state = MapCameraState(point, zoom: zoom ?? state?.zoom ?? 14);
  }
  @override
  Future<void> setCandidate(GeoPoint? value) async { candidate = value; }
  @override
  Future<void> setDestination(Destination? value) async { destination = value; }
  @override
  void setPinReveal(double progress) {}
  @override
  Future<void> setUserLocation(LocationFix? location, {required bool follow}) async {}
  @override
  Future<void> setMembers(List<MapMemberOverlay> members) async {}
  @override
  Future<void> setSharedPings(List<MapPingOverlay> pings) async {}
  @override
  void reset() { loaded = false; }
  @override
  void dispose() {}
}

class _Regions implements OfflineRegionRepository {
  List<OfflineRegion> value = [];
  @override
  Future<List<OfflineRegion>> load() async => value;
  @override
  Future<void> save(List<OfflineRegion> regions) async => value = regions;
}

class _Tiles implements OfflineTileBackend {
  @override
  Future<int?> estimate(OfflineRegion region) async => 100;
  @override
  Future<int> download(OfflineRegion region,
      void Function(double, int) onProgress) async => 100;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<bool> exists(String id) async => true;
  @override
  Future<void> setConnected(bool connected) async {}
}

void main() {
  testWidgets('compact header opens service status without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = DestinationController(locationProvider: _Location(),
      headingProvider: _Heading(), networkMonitor: _Network(), store: _Store());
    final error = ValueNotifier<String?>(null);
    await tester.pumpWidget(MaterialApp(home: MapScreen(
      controller: controller, mapProvider: _Map(),
      mapConfigured: false, mapError: error,
      configuration: const ServiceConfiguration(kakaoNativeAppKey: '',
        supabaseUrl: '', supabasePublishableKey: '',
        mapboxAccessToken: ''))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('설정 및 오프라인 지도'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('서비스 상태'));
    await tester.pumpAndSettle();
    expect(find.text('Android package'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    error.dispose();
  });

  testWidgets('swipe expands and collapses the compass continuously', (tester) async {
    final controller = DestinationController(
      locationProvider: _Location(), headingProvider: _Heading(),
      networkMonitor: _Network(), store: _Store());
    final error = ValueNotifier<String?>(null);
    await tester.pumpWidget(MaterialApp(home: MapScreen(
      controller: controller, mapProvider: _Map(),
      mapConfigured: false, mapError: error)));
    await tester.pump();
    final collapsed = tester.getSize(find.byType(CompassPanel)).height;
    expect(collapsed, 278);

    await tester.drag(find.byKey(const Key('compass_handle')), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(CompassPanel)).height, greaterThan(collapsed));

    await tester.drag(find.byKey(const Key('compass_handle')), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(CompassPanel)).height, collapsed);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    error.dispose();
  });

  testWidgets('selected point needs confirmation before becoming destination', (tester) async {
    final store = _Store();
    final controller = DestinationController(
      locationProvider: _Location(), headingProvider: _Heading(),
      networkMonitor: _Network(), store: store);
    final error = ValueNotifier<String?>(null);
    await tester.pumpWidget(MaterialApp(home: MapScreen(
      controller: controller, mapProvider: _Map(),
      mapConfigured: false, mapError: error)));
    await tester.pump();
    controller.selectPoint(const GeoPoint(37.5, 127));
    await tester.pump();
    expect(controller.destination, isNull);
    expect(find.byKey(const Key('confirm_destination')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_destination')));
    await tester.pumpAndSettle();
    expect(controller.destination?.point, const GeoPoint(37.5, 127));
    expect(store.value?.point, const GeoPoint(37.5, 127));

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    error.dispose();
  });

  testWidgets('switching keeps camera, candidate and compass while map changes',
      (tester) async {
    const center = GeoPoint(37.52, 127.1);
    final saved = Destination(point: const GeoPoint(37.53, 127.11),
      createdAt: DateTime.utc(2026), name: '서울숲');
    final store = _Store()..value = saved;
    final controller = DestinationController(locationProvider: _Location(),
      headingProvider: _Heading(), networkMonitor: _Network(), store: store);
    final online = _Map()..state = const MapCameraState(center,
      zoom: 12, bearing: 32, pitch: 24);
    final offline = _Map();
    final maps = OfflineMapController(repository: _Regions(), backend: _Tiles());
    await maps.start();
    await maps.download(maps.draft(center, 5));
    final mode = MapModeController(kakaoConfigured: true, offlineMaps: maps,
      switchDelay: const Duration(milliseconds: 1),
      recoveryDelay: const Duration(milliseconds: 1));
    final error = ValueNotifier<String?>(null);
    await tester.pumpWidget(MaterialApp(home: MapScreen(controller: controller,
      mapProvider: online, offlineMapProvider: offline,
      offlineMaps: maps, mapMode: mode,
      mapConfigured: true, mapError: error)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    controller.selectPoint(const GeoPoint(37.54, 127.12));
    await tester.pump();
    mode.update(connected: false, position: center);
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pump();
    expect(mode.mode, MapMode.offlineMapbox);
    expect(offline.state?.center, center);
    expect(offline.state?.zoom, 12);
    expect(offline.state?.bearing, 32);
    expect(offline.destination?.point, saved.point);
    expect(offline.candidate, const GeoPoint(37.54, 127.12));
    expect(find.byType(CompassPanel), findsOneWidget);
    offline.state = const MapCameraState(GeoPoint(37.51, 127.09),
      zoom: 10, bearing: 18);
    mode.update(position: const GeoPoint(38.0, 128.0));
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pump();
    expect(mode.mode, MapMode.mapUnavailable);
    expect(find.text('오프라인 · 이 지역의 지도가 없습니다.'), findsOneWidget);
    expect(find.byType(CompassPanel), findsOneWidget);
    mode.update(connected: true);
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pump();
    expect(mode.mode, MapMode.onlineKakao);
    expect(online.state?.zoom, 10);
    expect(online.state?.center, const GeoPoint(37.51, 127.09));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose(); mode.dispose(); maps.dispose(); error.dispose();
  });
}
