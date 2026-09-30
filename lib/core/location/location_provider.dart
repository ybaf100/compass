import '../geo_point.dart';

enum LocationAccess {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

enum LocationPrecision { unknown, precise, reduced }
enum LocationFailure { permissionDenied, serviceDisabled, plugin, timeout,
  accessCheck, stream }

class LocationProviderException implements Exception {
  const LocationProviderException(this.category);
  final LocationFailure category;
}

abstract class LocationDiagnosticsProvider {
  LocationPrecision get precision;
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
