import 'package:destination_compass/map/map_user_heading.dart';
import 'package:destination_compass/destination/bearing_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera rotation compensates screen heading', () {
    expect(MapUserHeading.display(90, 0), 90);
    expect(MapUserHeading.display(90, 45), 45);
    expect(MapUserHeading.display(90, 180), 270);
    expect(MapUserHeading.display(0, 359), 1);
  });
  test('359 to 0 and 0 to 359 stay shortest across rotated cameras', () {
    for (final bearing in [0.0, 45.0, 359.0]) {
      final a = MapUserHeading.display(359, bearing)!;
      final b = MapUserHeading.display(0, bearing)!;
      expect(BearingEngine.shortestDelta(a, b), 1);
      expect(BearingEngine.shortestDelta(b, a), -1);
    }
  });
  test('missing or invalid sensor values have no direction', () {
    expect(MapUserHeading.display(null, 0), isNull);
    expect(MapUserHeading.display(double.nan, 0), isNull);
    expect(MapUserHeading.display(90, double.infinity), isNull);
  });
}
