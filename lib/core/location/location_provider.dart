import '../geo_point.dart';

enum LocationAccess {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

class LocationFix {
  const LocationFix({
    required this.point,
    required this.accuracyMeters,
    required this.altitudeMeters,
  });

  final GeoPoint point;
  final double accuracyMeters;
  final double altitudeMeters;
}

abstract class LocationProvider {
  Future<LocationAccess> checkAccess({required bool requestPermission});
  Stream<LocationFix> get positions;
  Stream<bool> get serviceEnabled;
  Future<void> openAppSettings();
  Future<void> openLocationSettings();
}
