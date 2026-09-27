import 'package:destination_compass/core/compass/heading_filter.dart';
import 'package:destination_compass/destination/bearing_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('359 to 0 passes north without a long reverse turn', () {
    final filter = HeadingFilter();
    expect(filter.update(359), 359);
    final next = filter.update(0);
    expect(BearingEngine.shortestDelta(359, next), inInclusiveRange(0, 1));
  });

  test('small noise is ignored and large turns respond promptly', () {
    final filter = HeadingFilter();
    filter.update(10);
    expect(filter.update(10.4), 10);
    expect(filter.update(100), greaterThan(50));
  });

  test('reset discards the previous heading', () {
    final filter = HeadingFilter()..update(300);
    filter.reset();
    expect(filter.update(40), 40);
  });
}
