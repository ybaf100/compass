import 'package:destination_compass/core/compass/heading_provider.dart';
import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/core/location/location_provider.dart';
import 'package:destination_compass/core/network/network_monitor.dart';
import 'package:destination_compass/destination/destination_controller.dart';
import 'package:destination_compass/destination/destination_model.dart';
import 'package:destination_compass/destination/destination_store.dart';
import 'package:destination_compass/map/map_provider.dart';
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

class _Map implements MapProvider {
  @override
  Widget buildMap({required double bottomPadding,
    required ValueChanged<GeoPoint> onPicked,
    required void Function(GeoPoint, String) onNamedPlacePicked,
    required VoidCallback onLoaded,
    required VoidCallback onGesture,
    void Function(String memberId)? onMemberTapped,
  }) => const ColoredBox(color: Colors.blue);
  @override
  Future<void> moveCamera(GeoPoint point, {double? zoom}) async {}
  @override
  Future<void> setCandidate(GeoPoint? candidate) async {}
  @override
  Future<void> setDestination(Destination? destination) async {}
  @override
  void setPinReveal(double progress) {}
  @override
  Future<void> setUserLocation(LocationFix? location, {required bool follow}) async {}
  @override
  Future<void> setMembers(List<MapMemberOverlay> members) async {}
  @override
  Future<void> setSharedPings(List<MapPingOverlay> pings) async {}
  @override
  void reset() {}
  @override
  void dispose() {}
}

void main() {
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
}
