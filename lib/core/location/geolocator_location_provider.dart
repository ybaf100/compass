import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../diagnostics.dart';
import '../geo_point.dart';
import 'location_provider.dart';

class GeolocatorLocationProvider implements LocationProvider, LocationDiagnosticsProvider {
  @override
  LocationPrecision precision = LocationPrecision.unknown;
  @override
  Future<LocationAccess> checkAccess({required bool requestPermission}) async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    diagnosticEvent('location.service', enabled ? 'enabled' : 'disabled');
    if (!enabled) {
      return LocationAccess.serviceDisabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    diagnosticEvent('location.permission', permission.name);
    if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
      try {
        precision = await Geolocator.getLocationAccuracy() == LocationAccuracyStatus.precise
            ? LocationPrecision.precise : LocationPrecision.reduced;
      } catch (_) {
        precision = LocationPrecision.unknown;
      }
      diagnosticEvent('location.precision', precision.name);
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
  )).handleError((Object error) {
    final category = switch (error) {
      PermissionDeniedException() => LocationFailure.permissionDenied,
      LocationServiceDisabledException() => LocationFailure.serviceDisabled,
      MissingPluginException() || PlatformException() => LocationFailure.plugin,
      TimeoutException() => LocationFailure.timeout,
      _ => LocationFailure.stream,
    };
    throw LocationProviderException(category);
  });

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
