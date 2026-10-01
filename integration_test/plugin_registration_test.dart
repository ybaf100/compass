import 'package:destination_compass/core/compass/native_heading_provider.dart';
import 'package:destination_compass/core/network/network_monitor.dart';
import 'package:destination_compass/map/kakao_map_provider.dart';
import 'package:destination_compass/map/kakao_map_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UIScene engine registers plugins and custom native bridges', (tester) async {
    final network = await ConnectivityNetworkMonitor().current.timeout(const Duration(seconds: 10));
    expect(network.failure, isNull, reason: 'connectivity plugin must be registered');
    final preferences = await SharedPreferences.getInstance().timeout(const Duration(seconds: 10));
    await preferences.setBool('plugin_smoke_test', true);
    expect(preferences.getBool('plugin_smoke_test'), isTrue);
    await preferences.remove('plugin_smoke_test');
    await Geolocator.isLocationServiceEnabled().timeout(const Duration(seconds: 10));
    await Geolocator.checkPermission().timeout(const Duration(seconds: 10)); // No prompt or coordinates.
    await NativeHeadingProvider().heading.first.timeout(const Duration(seconds: 5));

    KakaoFailure? failure;
    final map = KakaoMapProvider(appKey: '', onFailure: (value) => failure = value);
    await map.refreshRuntimeIdentity().timeout(const Duration(seconds: 10));
    expect(map.diagnostics.value.runtimeBundleId, 'com.ybaf100.compass');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: map.buildMap(
      bottomPadding: 0, onPicked: (_) {}, onNamedPlacePicked: (_, _) {},
      onLoaded: () {}, onGesture: () {}))));
    for (var attempt = 0; attempt < 20 && failure == null; attempt++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(tester.takeException(), isNull);
    expect(failure, KakaoFailure.initialization,
      reason: 'Native platform view must exist; missing key fails safely');
    expect(map.diagnostics.value.keyPresent, isFalse);
    expect(map.diagnostics.value.sdkInitialized, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    map.dispose();
  });
}
