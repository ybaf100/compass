import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/core/location/location_provider.dart';
import 'package:destination_compass/destination/destination_model.dart';
import 'package:destination_compass/map/kakao_map_bridge.dart';
import 'package:destination_compass/map/kakao_map_provider.dart';
import 'package:destination_compass/map/kakao_map_state.dart';
import 'package:destination_compass/map/kakao_diagnostics.dart';
import 'package:destination_compass/map/map_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeKakaoBridge implements KakaoMapBridge {
  ValueChanged<Map<String, dynamic>>? listener;
  final calls = <(String, Map<String, dynamic>)>[];
  String? passedKey;
  String? bundleId = 'com.ybaf100.compass';
  @override
  Future<String?> runtimeBundleIdentifier() async => bundleId;
  @override
  Widget build({required String appKey,
      required ValueChanged<Map<String, dynamic>> onEvent}) {
    passedKey = appKey;
    listener = onEvent;
    return const SizedBox();
  }
  @override
  Future<void> send(String method, Map<String, dynamic> arguments) async {
    calls.add((method, arguments));
  }
  void emit(Map<String, dynamic> event) => listener?.call(event);
  @override
  void detach() { listener = null; }
  List<Map<String, dynamic>> get markers =>
    (calls.lastWhere((call) => call.$1 == 'overlays').$2['markers'] as List)
      .cast<Map<String, dynamic>>();
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  const own = GeoPoint(37.5, 127.0);
  const friend = GeoPoint(37.51, 127.01);

  test('native auth success lifecycle diagnostics are retained through loaded', () async {
    final bridge = FakeKakaoBridge();
    final provider = KakaoMapProvider(appKey: 'never-record-key', bridge: bridge);
    provider.buildMap(bottomPadding: 0, onPicked: (_) {},
      onNamedPlacePicked: (_, _) {}, onLoaded: () {}, onGesture: () {});
    await provider.refreshRuntimeIdentity();
    expect(provider.diagnostics.value.matchesBundleId('com.ybaf100.compass'), isTrue);
    for (final stage in KakaoStage.values.where((s) =>
        s != KakaoStage.failed && s != KakaoStage.prepareTimedOut && s != KakaoStage.timedOut)) {
      bridge.emit({'type': stage == KakaoStage.loaded ? 'loaded' : 'diagnostics',
        'stage': stage.name, 'keyPresent': true, 'sdkInitialized': true});
      expect(provider.diagnostics.value.stage, stage);
    }
    expect(provider.diagnostics.value.sdkInitialized, isTrue);
    provider.dispose();
  });

  for (final code in [400, 401, 403, 429, 499]) {
    test('auth code $code reaches diagnostics without raw SDK desc or key', () {
      final bridge = FakeKakaoBridge();
      KakaoFailure? failure;
      final provider = KakaoMapProvider(appKey: 'never-record-key', bridge: bridge,
        onFailure: (value) => failure = value);
      provider.buildMap(bottomPadding: 0, onPicked: (_) {},
        onNamedPlacePicked: (_, _) {}, onLoaded: () {}, onGesture: () {});
      bridge.emit({'type': 'failed', 'category': 'authentication',
        'stage': 'failed', 'authErrorCode': code, 'desc': 'never-record-key'});
      expect(failure, KakaoFailure.authentication);
      expect(provider.diagnostics.value.authErrorCode, code);
      expect(provider.diagnostics.value.authErrorLabel, startsWith('$code ·'));
      expect(provider.diagnostics.value.authErrorLabel, isNot(contains('never-record-key')));
      provider.dispose();
    });
  }

  test('499 retry diagnostic is not a terminal map failure before budget exhaustion', () {
    final bridge = FakeKakaoBridge();
    KakaoFailure? failure;
    final provider = KakaoMapProvider(appKey: 'test', bridge: bridge,
      onFailure: (value) => failure = value);
    provider.buildMap(bottomPadding: 0, onPicked: (_) {},
      onNamedPlacePicked: (_, _) {}, onLoaded: () {}, onGesture: () {});
    bridge.emit({'type': 'diagnostics', 'stage': 'failed', 'authErrorCode': 499,
      'retryCount': 2, 'retryPending': true});
    expect(failure, isNull);
    expect(provider.diagnostics.value.retryCount, 2);
    expect(provider.diagnostics.value.retryPending, isTrue);
    bridge.emit({'type': 'failed', 'category': 'authentication',
      'stage': 'failed', 'authErrorCode': 499, 'retryCount': 2, 'retryPending': false});
    expect(failure, KakaoFailure.authentication);
    provider.dispose();
  });

  for (final authArrived in [false, true]) {
    test('false prepare return with ${authArrived ? 'auth success' : 'SDK prepared'} continues loading', () {
      final bridge = FakeKakaoBridge();
      KakaoFailure? failure;
      var loaded = 0;
      final provider = KakaoMapProvider(appKey: 'test', bridge: bridge,
        onFailure: (value) => failure = value);
      provider.buildMap(bottomPadding: 0, onPicked: (_) {},
        onNamedPlacePicked: (_, _) {}, onLoaded: () => loaded++, onGesture: () {});
      bridge.emit({'type': 'diagnostics', 'stage': 'authenticating',
        'prepareReturn': false, 'enginePrepared': false, 'engineActive': false,
        'authCallback': 'none', 'nativeTimeoutManaged': true});
      expect(failure, isNull);
      expect(provider.diagnostics.value.prepareReturn, isFalse);
      expect(provider.diagnostics.value.engineActive, isFalse);
      bridge.emit({'type': 'loaded', 'stage': 'loaded', 'enginePrepared': true,
        'engineActive': true, 'authCallback': authArrived ? 'succeeded' : 'none'});
      expect(loaded, 1);
      expect(failure, isNull);
      expect(provider.diagnostics.value.enginePrepared, isTrue);
      expect(provider.diagnostics.value.engineActive, isTrue);
      provider.dispose();
    });
  }

  test('prepare timeout and rendering timeout are distinct native failures', () {
    final bridge = FakeKakaoBridge();
    KakaoFailure? failure;
    final provider = KakaoMapProvider(appKey: 'test', bridge: bridge,
      onFailure: (value) => failure = value);
    provider.buildMap(bottomPadding: 0, onPicked: (_) {},
      onNamedPlacePicked: (_, _) {}, onLoaded: () {}, onGesture: () {});
    bridge.emit({'type': 'diagnostics', 'stage': 'prepareTimedOut',
      'prepareReturn': false, 'retryPending': true, 'retryCount': 1});
    expect(failure, isNull); // Recoverable preparation deadline stays native.
    bridge.emit({'type': 'failed', 'stage': 'prepareTimedOut', 'category': 'prepareTimeout'});
    expect(failure, KakaoFailure.prepareTimeout);
    bridge.emit({'type': 'failed', 'stage': 'timedOut', 'category': 'timeout'});
    expect(failure, KakaoFailure.timeout);
    provider.dispose();
  });

  test('engine diagnostics whitelist opaque state descriptions and retain snapshots', () {
    final value = const KakaoDiagnostics().apply({'prepareReturn': false,
      'enginePrepared': true, 'engineActive': false, 'authCallback': 'none',
      'engineStateSummary': 'prepared', 'stateDescriptionAvailable': true,
      'stateDescription': 'secret-key location=37.5,127.0'});
    expect(value.engineStateSummary, KakaoEngineSummary.prepared);
    expect(value.withRuntimeBundleId('com.example').enginePrepared, isTrue);
    expect(value.withRuntimeBundleId('com.example').prepareReturn, isFalse);
    expect(value.apply({'prepareReturn': null}).prepareReturn, isNull);
    expect(value.apply({'engineStateSummary': 'secret-key'}).engineStateSummary,
      KakaoEngineSummary.prepared);
  });

  test('native ready/failure, tap, member tap and gesture events', () async {
    final bridge = FakeKakaoBridge();
    KakaoFailure? error;
    String? tappedMember;
    GeoPoint? selected;
    var loaded = 0, gestures = 0;
    final provider = KakaoMapProvider(appKey: 'test-native-key', bridge: bridge,
      onFailure: (message) => error = message);
    provider.buildMap(bottomPadding: 250, onPicked: (point) => selected = point,
      onNamedPlacePicked: (_, _) {}, onLoaded: () => loaded++,
      onGesture: () => gestures++, onMemberTapped: (id) => tappedMember = id);
    expect(bridge.passedKey, 'test-native-key');
    bridge.emit({'type': 'attached'});
    bridge.emit({'type': 'loaded'});
    bridge.emit({'type': 'tap', 'latitude': 37.52, 'longitude': 127.1});
    bridge.emit({'type': 'memberTap', 'id': 'friend-1'});
    bridge.emit({'type': 'gesture'});
    await flush();
    expect(loaded, 1);
    expect(selected, const GeoPoint(37.52, 127.1));
    expect(tappedMember, 'friend-1');
    expect(gestures, 1);
    expect(bridge.calls.any((call) => call.$1 == 'padding' &&
      call.$2['bottom'] == 250), isTrue);
    bridge.emit({'type': 'failed', 'category': 'authentication'});
    expect(error, KakaoFailure.authentication);
    bridge.emit({'type': 'failed', 'category': 'addView'});
    expect(error, KakaoFailure.addView);
    provider.dispose();
    bridge.emit({'type': 'tap', 'latitude': 0, 'longitude': 0});
    expect(selected, const GeoPoint(37.52, 127.1));
  });

  test('stable destination/candidate/member/ping overlays reconcile in place', () async {
    final bridge = FakeKakaoBridge();
    final provider = KakaoMapProvider(appKey: 'test', bridge: bridge);
    provider.buildMap(bottomPadding: 0, onPicked: (_) {},
      onNamedPlacePicked: (_, _) {}, onLoaded: () {}, onGesture: () {});
    bridge.emit({'type': 'attached'});
    bridge.emit({'type': 'loaded'});
    await provider.setUserLocation(const LocationFix(point: own,
      accuracyMeters: 6, altitudeMeters: 3), follow: false);
    await provider.setDestination(Destination(point: friend,
      name: '서울숲', createdAt: DateTime.utc(2026)));
    await provider.setCandidate(own);
    await provider.setMembers([MapMemberOverlay(id: 'f1', name: '철수',
      point: friend, updatedAt: DateTime.utc(2026), isStale: true)]);
    await provider.setSharedPings(const [MapPingOverlay(id: 'p1', point: own,
      label: 'Ping')]);
    expect(bridge.markers.map((item) => item['id']),
      ['user', 'candidate', 'destination', 'member:f1', 'ping:p1']);
    expect(bridge.markers[3]['kind'], 'stale');
    await provider.setMembers([MapMemberOverlay(id: 'f1', name: '철수',
      point: own, updatedAt: DateTime.utc(2026), isStale: false)]);
    expect(bridge.markers[3]['id'], 'member:f1');
    expect(bridge.markers[3]['latitude'], own.latitude);
    await provider.setCandidate(null);
    await provider.setSharedPings(const []);
    expect(bridge.markers.map((item) => item['id']),
      ['user', 'destination', 'member:f1']);
    provider.dispose();
  });

  test('camera handoff keeps center, approximate zoom and orientation', () async {
    final bridge = FakeKakaoBridge();
    final provider = KakaoMapProvider(appKey: 'test', bridge: bridge);
    await provider.restoreCamera(const MapCameraState(own,
      zoom: 13.6, bearing: 359, pitch: 25));
    provider.buildMap(bottomPadding: 0, onPicked: (_) {},
      onNamedPlacePicked: (_, _) {}, onLoaded: () {}, onGesture: () {});
    bridge.emit({'type': 'attached'});
    bridge.emit({'type': 'loaded'});
    await flush();
    final camera = bridge.calls.lastWhere((call) => call.$1 == 'camera').$2;
    expect(camera['zoom'], 14);
    expect(camera['bearing'], 359);
    bridge.emit({'type': 'camera', 'latitude': 37.6, 'longitude': 127.2,
      'zoom': 12, 'bearing': 2.0, 'pitch': 20.0});
    expect(provider.cameraState?.center, const GeoPoint(37.6, 127.2));
    expect(provider.cameraState?.zoom, 12);
    expect(provider.cameraState?.bearing, 2);
    provider.dispose();
  });
}
