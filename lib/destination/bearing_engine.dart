import 'dart:math' as math;

import '../core/geo_point.dart';

/// Angles are clockwise from true north; distances are great-circle meters.
abstract final class BearingEngine {
  static const double earthRadiusMeters = 6371008.8;

  static double normalize(double degrees) {
    if (!degrees.isFinite) throw ArgumentError.value(degrees, 'degrees');
    final result = degrees % 360;
    return result == 0 ? 0 : result;
  }

  /// Signed shortest turn from [from] to [to] in [-180, 180).
  static double shortestDelta(double from, double to) =>
      (normalize(to) - normalize(from) + 540) % 360 - 180;

  static double relativeAngle(double bearing, double heading) =>
      normalize(bearing - heading);

  static double bearing(GeoPoint origin, GeoPoint destination) {
    _validate(origin, destination);
    if (origin == destination) return 0;
    final latitude1 = _radians(origin.latitude);
    final latitude2 = _radians(destination.latitude);
    final deltaLongitude =
        _radians(destination.longitude - origin.longitude);
    final y = math.sin(deltaLongitude) * math.cos(latitude2);
    final x = math.cos(latitude1) * math.sin(latitude2) -
        math.sin(latitude1) * math.cos(latitude2) *
            math.cos(deltaLongitude);
    return normalize(math.atan2(y, x) * 180 / math.pi);
  }

  static double distanceMeters(GeoPoint origin, GeoPoint destination) {
    _validate(origin, destination);
    final latDelta = _radians(destination.latitude - origin.latitude);
    final lonDelta = _radians(destination.longitude - origin.longitude);
    final lat1 = _radians(origin.latitude);
    final lat2 = _radians(destination.latitude);
    final a = math.pow(math.sin(latDelta / 2), 2) +
        math.cos(lat1) * math.cos(lat2) *
            math.pow(math.sin(lonDelta / 2), 2);
    return earthRadiusMeters * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }

  static void _validate(GeoPoint a, GeoPoint b) {
    if (!a.isValid || !b.isValid) {
      throw ArgumentError('Invalid geographic coordinate');
    }
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}
