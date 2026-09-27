import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/destination/destination_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved destination restores coordinates, name, and creation time', () {
    final destination = Destination(
      point: const GeoPoint(37.5665, 126.978),
      name: '서울시청',
      createdAt: DateTime.utc(2026, 9, 27, 5, 30),
    );
    final restored = Destination.fromJson(
      Map<String, dynamic>.from(destination.toJson()),
    );
    expect(restored?.point, destination.point);
    expect(restored?.name, destination.name);
    expect(restored?.createdAt, destination.createdAt);
  });

  test('corrupt or out of range coordinates are ignored', () {
    expect(Destination.fromJson({
      'latitude': 200,
      'longitude': 127,
      'createdAt': '2026-09-27T05:30:00Z',
    }), isNull);
  });
}
