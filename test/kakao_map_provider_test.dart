import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/core/location/location_provider.dart';
import 'package:destination_compass/destination/destination_model.dart';
import 'package:destination_compass/map/kakao_map_bridge.dart';
import 'package:destination_compass/map/kakao_map_provider.dart';
import 'package:destination_compass/map/map_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeKakaoBridge implements KakaoMapBridge {
  ValueChanged<Map<String, dynamic>>? listener;
  final calls = <(String, Map<String, dynamic>)>[];
  String? passedKey;
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

  test('native ready/failure, tap, member tap and gesture events', () async {
    final bridge = FakeKakaoBridge();
    String? error, tappedMember;
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
    bridge.emit({'type': 'failed'});
    expect(error, contains('인증'));
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
