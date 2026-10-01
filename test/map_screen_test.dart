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
import 'package:destination_compass/map/kakao_map_state.dart';
import 'package:destination_compass/map/kakao_diagnostics.dart';
import 'package:destination_compass/offline/offline_map_controller.dart';
import 'package:destination_compass/offline/offline_region.dart';
import 'package:destination_compass/offline/offline_region_repository.dart';
import 'package:destination_compass/offline/offline_tile_backend.dart';
import 'package:destination_compass/ui/compass_panel.dart';
import 'package:destination_compass/ui/map_screen.dart';
import 'package:destination_compass/ui/service_status_sheet.dart';
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
  NetworkStatus status = const NetworkStatus(NetworkState.available);
  @override
  Future<NetworkStatus> get current async => status;
  @override
  Stream<NetworkStatus> get changes => const Stream.empty();
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

class _Map implements MapProvider, CameraAwareMapProvider, UserHeadingMapProvider {
  final headings = <double?>[];
  int overlayUpdates = 0;
  @override
  Future<void> setUserHeading(double? heading) async { headings.add(heading); }
  MapCameraState? state;
  Destination? destination;
  GeoPoint? candidate;
  bool loaded = false;
  bool emitLoaded = true;
  int resets = 0;
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
    if (!loaded && emitLoaded) {
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
  Future<void> setCandidate(GeoPoint? value) async { candidate = value; overlayUpdates++; }
  @override
  Future<void> setDestination(Destination? value) async { destination = value; overlayUpdates++; }
  @override
  void setPinReveal(double progress) {}
  @override
  Future<void> setUserLocation(LocationFix? location, {required bool follow}) async {}
  @override
  Future<void> setMembers(List<MapMemberOverlay> members) async {}
  @override
  Future<void> setSharedPings(List<MapPingOverlay> pings) async {}
  @override
  void reset() { loaded = false; resets++; }
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
  testWidgets('heading listener uses filtered values without resending destination/candidate', (tester) async {
    final controller = DestinationController(locationProvider: _Location(),
      headingProvider: _Heading(), networkMonitor: _Network(), store: _Store());
    final map = _Map();
    final error = ValueNotifier<KakaoFailure?>(null);
    await tester.pumpWidget(MaterialApp(home: MapScreen(controller: controller,
      mapProvider: map, mapConfigured: true, mapError: error)));
    await tester.pump();
    await tester.pump();
    final count = map.overlayUpdates;
    controller.heading.value = const HeadingReading(degrees: 270, isTrueNorth: false);
    controller.filteredHeading.value = 359;
    controller.filteredHeading.value = 0;
    await tester.pump();
    expect(map.headings.skip(map.headings.length - 2), [359, 0]);
    expect(map.headings, isNot(contains(270)));
    expect(map.overlayUpdates, count);
    await tester.pumpWidget(const SizedBox.shrink());
    final calls = map.headings.length;
    controller.filteredHeading.value = 45;
    expect(map.headings.length, calls);
    controller.dispose(); error.dispose();
  });
  testWidgets('compact header opens service status without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = DestinationController(locationProvider: _Location(),
      headingProvider: _Heading(), networkMonitor: _Network(), store: _Store());
    final error = ValueNotifier<KakaoFailure?>(null);
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
    await tester.scrollUntilVisible(find.text('Android package'), 250,
      scrollable: find.descendant(of: find.byType(ServiceStatusSheet),
        matching: find.byType(Scrollable)));
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
    final error = ValueNotifier<KakaoFailure?>(null);
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
    final error = ValueNotifier<KakaoFailure?>(null);
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
    final error = ValueNotifier<KakaoFailure?>(null);
    await tester.pumpWidget(MaterialApp(home: MapScreen(controller: controller,
      mapProvider: online, offlineMapProvider: offline,
      offlineMaps: maps, mapMode: mode,
      mapConfigured: true, mapError: error)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    controller.selectPoint(const GeoPoint(37.54, 127.12));
    await tester.pump();
    mode.update(networkState: NetworkState.unavailable, position: center);
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
    mode.update(networkState: NetworkState.available);
    await tester.pump(const Duration(milliseconds: 5));
    await tester.pump();
    expect(mode.mode, MapMode.onlineKakao);
    expect(online.state?.zoom, 10);
    expect(online.state?.center, const GeoPoint(37.51, 127.09));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose(); mode.dispose(); maps.dispose(); error.dispose();
  });

  testWidgets('unknown still builds Kakao; SDK timeout is not labeled offline; resume retries', (tester) async {
    final network = _Network()..status = const NetworkStatus.unknown(failure: NetworkFailure.plugin);
    final controller = DestinationController(locationProvider: _Location(),
      headingProvider: _Heading(), networkMonitor: network, store: _Store());
    final maps = OfflineMapController(repository: _Regions(), backend: null);
    final mode = MapModeController(kakaoConfigured: true, offlineMaps: maps,
      switchDelay: const Duration(milliseconds: 1), recoveryDelay: const Duration(milliseconds: 1));
    final map = _Map()..emitLoaded = false;
    final error = ValueNotifier<KakaoFailure?>(null);
    await tester.pumpWidget(MaterialApp(home: MapScreen(controller: controller,
      mapProvider: map, offlineMaps: maps, mapMode: mode,
      mapConfigured: true, mapError: error)));
    await tester.pump();
    expect(mode.mode, MapMode.onlineKakao);
    expect(find.text('연결 상태를 확인하는 중입니다.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 19));
    await tester.pump(const Duration(milliseconds: 10));
    expect(error.value, KakaoFailure.timeout);
    expect(find.text('카카오 지도 응답이 없습니다.'), findsOneWidget);
    expect(find.text('오프라인 · 이 지역의 지도가 없습니다.'), findsNothing);
    expect(controller.networkState, NetworkState.unknown);
    map.emitLoaded = true;
    network.status = const NetworkStatus(NetworkState.available);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(); await tester.pump(const Duration(milliseconds: 10)); await tester.pump();
    expect(controller.networkState, NetworkState.available);
    expect(mode.mode, MapMode.onlineKakao);
    expect(error.value, isNull);
    expect(find.byType(CompassPanel), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose(); mode.dispose(); maps.dispose(); error.dispose();
  });

  testWidgets('resume preserves in-flight auth and pauses timeout in background', (tester) async {
    final controller = DestinationController(locationProvider: _Location(),
      headingProvider: _Heading(), networkMonitor: _Network(), store: _Store());
    final maps = OfflineMapController(repository: _Regions(), backend: null);
    final mode = MapModeController(kakaoConfigured: true, offlineMaps: maps);
    final map = _Map()..emitLoaded = false;
    final error = ValueNotifier<KakaoFailure?>(null);
    await tester.pumpWidget(MaterialApp(home: MapScreen(controller: controller,
      mapProvider: map, offlineMaps: maps, mapMode: mode,
      mapConfigured: true, mapError: error)));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 20));
    expect(error.value, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(map.resets, 0);
    expect(mode.attempt, 0);
    expect(mode.mode, MapMode.onlineKakao);
    await tester.pump(const Duration(seconds: 17));
    expect(error.value, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose(); mode.dispose(); maps.dispose(); error.dispose();
  });

  testWidgets('native prepare retry deadline is not preempted by Flutter timeout', (tester) async {
    final controller = DestinationController(locationProvider: _Location(),
      headingProvider: _Heading(), networkMonitor: _Network(), store: _Store());
    final maps = OfflineMapController(repository: _Regions(), backend: null);
    final mode = MapModeController(kakaoConfigured: true, offlineMaps: maps,
      switchDelay: const Duration(milliseconds: 1));
    final map = _Map()..emitLoaded = false;
    final error = ValueNotifier<KakaoFailure?>(null);
    final diagnostics = ValueNotifier(const KakaoDiagnostics(
      nativeTimeoutManaged: true, prepareReturn: false, enginePrepared: false,
      engineActive: false, stage: KakaoStage.authenticating));
    await tester.pumpWidget(MaterialApp(home: MapScreen(controller: controller,
      mapProvider: map, offlineMaps: maps, mapMode: mode,
      mapConfigured: true, mapError: error, kakaoDiagnostics: diagnostics)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 19));
    expect(error.value, isNull);
    expect(map.resets, 0);
    expect(mode.mode, MapMode.onlineKakao);
    error.value = KakaoFailure.prepareTimeout; // Native budget exhausted.
    await tester.pump(const Duration(milliseconds: 10)); await tester.pump();
    expect(mode.kakaoState, KakaoState.timedOut);
    expect(find.text('카카오 지도 준비 응답이 없습니다.'), findsOneWidget);
    expect(find.byType(CompassPanel), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose(); mode.dispose(); maps.dispose(); error.dispose(); diagnostics.dispose();
  });

  testWidgets('Kakao auth failure with available network reports SDK failure', (tester) async {
    final controller = DestinationController(locationProvider: _Location(),
      headingProvider: _Heading(), networkMonitor: _Network(), store: _Store());
    final maps = OfflineMapController(repository: _Regions(), backend: null);
    final mode = MapModeController(kakaoConfigured: true, offlineMaps: maps,
      switchDelay: const Duration(milliseconds: 1));
    final error = ValueNotifier<KakaoFailure?>(null);
    await tester.pumpWidget(MaterialApp(home: MapScreen(controller: controller,
      mapProvider: _Map(), offlineMaps: maps, mapMode: mode,
      mapConfigured: true, mapError: error)));
    await tester.pump();
    error.value = KakaoFailure.authentication;
    await tester.pump(const Duration(milliseconds: 10)); await tester.pump();
    expect(controller.networkState, NetworkState.available);
    expect(mode.failure, KakaoFailure.authentication);
    expect(find.text('카카오 지도 연결에 실패했습니다.'), findsOneWidget);
    expect(find.text('오프라인 · 이 지역의 지도가 없습니다.'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(error.value, KakaoFailure.authentication);
    expect(mode.attempt, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose(); mode.dispose(); maps.dispose(); error.dispose();
  });
}
