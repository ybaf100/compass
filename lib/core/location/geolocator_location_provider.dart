import 'package:geolocator/geolocator.dart';

import '../geo_point.dart';
import 'location_provider.dart';

class GeolocatorLocationProvider implements LocationProvider {
  @override
  Future<LocationAccess> checkAccess({required bool requestPermission}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationAccess.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    return switch (permission) {
      LocationPermission.always || LocationPermission.whileInUse =>
        LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      LocationPermission.denied => LocationAccess.denied,
      LocationPermission.unableToDetermine => LocationAccess.denied,
    };
  }

  @override
  Stream<LocationFix> get positions => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 3,
    ),
  ).map((position) => LocationFix(
    point: GeoPoint(position.latitude, position.longitude),
    accuracyMeters: position.accuracy,
    altitudeMeters: position.altitude,
  ));

  @override
  Stream<bool> get serviceEnabled => Geolocator.getServiceStatusStream()
      .map((status) => status == ServiceStatus.enabled);

  @override
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}
