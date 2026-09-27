import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/destination/bearing_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const origin = GeoPoint(0, 0);

  test('angle normalization stays in [0, 360)', () {
    expect(BearingEngine.normalize(360), 0);
    expect(BearingEngine.normalize(-1), 359);
    expect(BearingEngine.normalize(721), 1);
  });

  test('shortest turn crosses north in both directions', () {
    expect(BearingEngine.shortestDelta(359, 0), 1);
    expect(BearingEngine.shortestDelta(0, 359), -1);
    expect(BearingEngine.shortestDelta(10, 350), -20);
    expect(BearingEngine.shortestDelta(350, 10), 20);
  });

  test('relative angle and compass heading share true north', () {
    expect(BearingEngine.relativeAngle(0, 359), 1);
    expect(BearingEngine.relativeAngle(359, 0), 359);
    expect(BearingEngine.relativeAngle(90, 90), 0);
  });

  test('initial bearing resolves cardinal points', () {
    expect(BearingEngine.bearing(origin, const GeoPoint(1, 0)), closeTo(0, 1e-8));
    expect(BearingEngine.bearing(origin, const GeoPoint(0, 1)), closeTo(90, 1e-8));
    expect(BearingEngine.bearing(origin, const GeoPoint(-1, 0)), closeTo(180, 1e-8));
    expect(BearingEngine.bearing(origin, const GeoPoint(0, -1)), closeTo(270, 1e-8));
  });

  test('great-circle distance is symmetric and zero at origin', () {
    const east = GeoPoint(0, 1);
    expect(BearingEngine.distanceMeters(origin, origin), 0);
    expect(BearingEngine.distanceMeters(origin, east), closeTo(111195, 100));
    expect(BearingEngine.distanceMeters(east, origin),
        closeTo(BearingEngine.distanceMeters(origin, east), 1e-8));
  });

  test('invalid coordinates are rejected', () {
    expect(() => BearingEngine.distanceMeters(origin, const GeoPoint(91, 0)),
        throwsArgumentError);
  });
}
