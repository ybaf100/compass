import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:destination_compass/core/compass/heading_provider.dart';
import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/core/location/location_provider.dart';
import 'package:destination_compass/core/network/network_monitor.dart';
import 'package:destination_compass/destination/destination_controller.dart';
import 'package:destination_compass/destination/destination_model.dart';
import 'package:destination_compass/destination/destination_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Network implements NetworkMonitor {
  final events = StreamController<NetworkStatus>.broadcast();
  NetworkStatus value = const NetworkStatus(NetworkState.available);
  Future<NetworkStatus> Function()? check;
  int checks = 0;
  @override
  Future<NetworkStatus> get current async {
    checks++;
    return check != null ? await check!() : value;
  }
  @override
  Stream<NetworkStatus> get changes => events.stream;
}

class _Location implements LocationProvider {
  final events = StreamController<LocationFix>.broadcast();
  LocationAccess access = LocationAccess.denied;
  @override
  Future<LocationAccess> checkAccess({required bool requestPermission}) async => access;
  @override
  Stream<LocationFix> get positions => events.stream;
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

class _Store implements DestinationStore {
  @override
  Future<Destination?> load() async => null;
  @override
  Future<void> save(Destination? destination) async {}
}

DestinationController controllerFor(_Network network, _Location location) =>
    DestinationController(networkMonitor: network, locationProvider: location,
      headingProvider: _Heading(), store: _Store());

void main() {
  test('normalization requires explicit none; empty is unknown and Wi-Fi wins', () {
    expect(ConnectivityNetworkMonitor.normalize([]).state, NetworkState.unknown);
    expect(ConnectivityNetworkMonitor.normalize([ConnectivityResult.none]).state,
      NetworkState.unavailable);
    for (final interface in [ConnectivityResult.wifi, ConnectivityResult.ethernet,
      ConnectivityResult.mobile, ConnectivityResult.other]) {
      expect(ConnectivityNetworkMonitor.normalize([interface]).state, NetworkState.available);
    }
    expect(ConnectivityNetworkMonitor.normalize([ConnectivityResult.none,
      ConnectivityResult.wifi]).state, NetworkState.available);
  });

  test('plugin check failure is unknown, not unavailable', () async {
    final monitor = ConnectivityNetworkMonitor(
      check: () async => throw MissingPluginException('private exception text'),
      changes: const Stream.empty());
    final status = await monitor.current;
    expect(status.state, NetworkState.unknown);
    expect(status.failure, NetworkFailure.plugin);
  });

  test('raw stream failure is unknown and later Wi-Fi recovers on same listener', () async {
    final raw = StreamController<List<ConnectivityResult>>();
    final monitor = ConnectivityNetworkMonitor(check: () async => [], changes: raw.stream);
    final statuses = <NetworkStatus>[];
    final subscription = monitor.changes.listen(statuses.add);
    raw.addError(MissingPluginException());
    raw.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    expect(statuses.map((s) => s.state), [NetworkState.unknown, NetworkState.available]);
    expect(statuses.first.failure, NetworkFailure.plugin);
    await subscription.cancel(); await raw.close();
  });

  testWidgets('initial unknown and controller check exception stay unknown', (tester) async {
    final network = _Network()..check = () async => throw MissingPluginException();
    final location = _Location(); final controller = controllerFor(network, location);
    expect(controller.networkState, NetworkState.unknown);
    await controller.start(); await tester.pump();
    expect(controller.networkState, NetworkState.unknown);
    expect(controller.networkStatus.failure, NetworkFailure.plugin);
    controller.dispose(); await network.events.close(); await location.events.close();
  });

  testWidgets('controller stream error becomes unknown and none/Wi-Fi recover', (tester) async {
    final network = _Network(); final location = _Location();
    final controller = controllerFor(network, location);
    await controller.start(); await tester.pump();
    network.events.addError(MissingPluginException()); await tester.pump();
    expect(controller.networkState, NetworkState.unknown);
    network.events.add(const NetworkStatus(NetworkState.unavailable)); await tester.pump();
    expect(controller.networkState, NetworkState.unavailable);
    network.events.add(const NetworkStatus(NetworkState.available)); await tester.pump();
    expect(controller.networkState, NetworkState.available);
    controller.dispose(); await network.events.close(); await location.events.close();
  });

  testWidgets('foreground recheck clears old offline; retries are bounded', (tester) async {
    final network = _Network()..value = const NetworkStatus(NetworkState.unavailable);
    final location = _Location(); final controller = controllerFor(network, location);
    await controller.start(); await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(network.checks, 3);
    await tester.pump(const Duration(seconds: 10));
    expect(network.checks, 3);
    network.value = const NetworkStatus(NetworkState.available);
    await controller.onAppResume();
    expect(controller.networkState, NetworkState.available);
    expect(network.checks, 4);
    controller.dispose(); await network.events.close(); await location.events.close();
  });

  testWidgets('late connectivity query cannot overwrite a newer Wi-Fi event', (tester) async {
    final pending = Completer<NetworkStatus>();
    final network = _Network()..check = () => pending.future;
    final location = _Location(); final controller = controllerFor(network, location);
    await controller.start();
    network.events.add(const NetworkStatus(NetworkState.available)); await tester.pump();
    pending.complete(const NetworkStatus(NetworkState.unavailable)); await tester.pump();
    expect(controller.networkState, NetworkState.available);
    controller.dispose(); await network.events.close(); await location.events.close();
  });

  testWidgets('location fix after 15 seconds is still accepted without offline implication', (tester) async {
    final network = _Network(); final location = _Location()..access = LocationAccess.granted;
    final controller = controllerFor(network, location);
    await controller.start();
    await tester.pump(const Duration(seconds: 16));
    expect(controller.locationState, LocationState.acquiring);
    expect(controller.firstFixDelayed, isTrue);
    expect(controller.locationFailure, isNull);
    location.events.add(const LocationFix(point: GeoPoint(37.5, 127),
      accuracyMeters: 4, altitudeMeters: 0)); await tester.pump();
    expect(controller.locationState, LocationState.ready);
    expect(controller.firstFixDelayed, isFalse);
    expect(controller.networkState, NetworkState.available);
    controller.dispose(); await network.events.close(); await location.events.close();
  });

  testWidgets('actual location stream error is distinct from delayed first fix', (tester) async {
    final network = _Network(); final location = _Location()..access = LocationAccess.granted;
    final controller = controllerFor(network, location);
    await controller.start();
    location.events.addError(StateError('private sensor error')); await tester.pump();
    expect(controller.locationState, LocationState.unavailable);
    expect(controller.locationFailure, LocationFailure.stream);
    expect(controller.networkState, NetworkState.available);
    controller.dispose(); await network.events.close(); await location.events.close();
  });

  testWidgets('denied permission does not start location stream or first-fix timeout', (tester) async {
    final network = _Network(); final location = _Location();
    final controller = controllerFor(network, location);
    await controller.start();
    expect(controller.locationState, LocationState.permissionDenied);
    expect(location.events.hasListener, isFalse);
    await tester.pump(const Duration(seconds: 20));
    expect(controller.locationState, LocationState.permissionDenied);
    controller.dispose(); await network.events.close(); await location.events.close();
  });
}
