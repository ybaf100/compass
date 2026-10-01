import 'package:destination_compass/core/compass/heading_filter.dart';
import 'package:destination_compass/core/compass/heading_provider.dart';
import 'package:destination_compass/core/compass/native_heading_provider.dart';
import 'package:destination_compass/destination/bearing_engine.dart';
import 'package:destination_compass/map/heading_diagnostics.dart';
import 'package:destination_compass/map/map_user_heading.dart';
import 'package:destination_compass/core/config/service_configuration.dart';
import 'package:destination_compass/ui/service_status_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fake CoreLocation outputs verify transport/filter conventions only.
  // Real screen-top north/east accuracy requires the physical iPad checklist.
  for (final interface in [HeadingOrientation.landscapeLeft,
    HeadingOrientation.landscapeRight]) {
    for (final degrees in [0.0, 90.0]) {
      test('fake SDK ${interface.name} screen-top ${degrees == 0 ? 'north' : 'east'} stays unchanged', () {
        final applied = interface == HeadingOrientation.landscapeLeft
            ? HeadingOrientation.landscapeRight : HeadingOrientation.landscapeLeft;
        final reading = NativeHeadingProvider.decodeReading({
          'heading': degrees, 'trueNorth': true, 'accuracy': 2,
          'interfaceOrientation': interface.name, 'headingOrientation': applied.name,
        })!;
        expect(reading.interfaceOrientation, interface);
        expect(reading.headingOrientation, applied);
        expect(reading.degrees, degrees);
        final filtered = HeadingFilter().update(reading.degrees);
        expect(MapUserHeading.display(filtered, 0), degrees);
      });
    }
  }

  test('orientation diagnostics are whitelisted and Android remains compatible', () {
    final invalid = NativeHeadingProvider.decodeReading({'heading': 90,
      'interfaceOrientation': 'do-not-expose-key', 'headingOrientation': 123});
    expect(invalid!.interfaceOrientation, isNull);
    expect(invalid.headingOrientation, isNull);
    final android = NativeHeadingProvider.decodeReading({'heading': 90, 'trueNorth': false})!;
    expect(android.degrees, 90);
    expect(android.interfaceOrientation, isNull);
    expect(android.headingOrientation, isNull);
  });

  test('invalid sensor payloads do not create heading readings', () {
    for (final payload in [null, 'do-not-expose-key', {'heading': double.nan},
      {'heading': double.infinity}, {'heading': '90'}]) {
      expect(NativeHeadingProvider.decodeReading(payload), isNull);
    }
  });

  test('diagnostic snapshot compensates camera once without touching readings', () {
    const reading = HeadingReading(degrees: 82, isTrueNorth: true,
      interfaceOrientation: HeadingOrientation.landscapeLeft,
      headingOrientation: HeadingOrientation.landscapeRight);
    final snapshot = HeadingDiagnostics.snapshot(reading: reading,
      filteredHeading: 82, cameraBearing: 15);
    expect(snapshot.interfaceOrientation, HeadingOrientation.landscapeLeft);
    expect(snapshot.headingOrientation, HeadingOrientation.landscapeRight);
    expect(snapshot.filteredHeading, 82);
    expect(snapshot.cameraBearing, 15);
    expect(snapshot.displayHeading, 67);
    expect(reading.degrees, 82);
  });

  test('heading 90 camera 0 is 90 and camera 90 is 0', () {
    expect(MapUserHeading.display(90, 0), 90);
    expect(MapUserHeading.display(90, 90), 0);
    expect(MapUserHeading.display(0, 90), 270);
  });

  test('diagnostics never assume north-up when camera is unavailable', () {
    final snapshot = HeadingDiagnostics.snapshot(filteredHeading: 90);
    expect(snapshot.filteredHeading, 90);
    expect(snapshot.displayHeading, isNull);
    expect(HeadingDiagnostics.snapshot(filteredHeading: double.nan,
      cameraBearing: double.infinity).displayHeading, isNull);
  });

  for (final pair in [(359.0, 0.0), (0.0, 359.0)]) {
    test('${pair.$1} to ${pair.$2} retains shortest filtered route', () {
      final filter = HeadingFilter();
      final before = filter.update(pair.$1);
      final after = filter.update(pair.$2);
      final delta = BearingEngine.shortestDelta(before, after);
      expect(delta.abs(), lessThan(1));
      expect(delta.sign, pair.$1 == 359 ? 1 : -1);
    });
  }

  testWidgets('service diagnostics show orientation and angle snapshot, not keys or coordinates', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ServiceStatusSheet(
      kakao: ConfigurationStatus.configured, supabase: ConfigurationStatus.missing,
      mapbox: ConfigurationStatus.missing,
      headingDiagnostics: HeadingDiagnostics.snapshot(
        reading: const HeadingReading(degrees: 82, isTrueNorth: true,
          interfaceOrientation: HeadingOrientation.landscapeLeft,
          headingOrientation: HeadingOrientation.landscapeRight),
        filteredHeading: 82, cameraBearing: 15)))));
    for (final entry in {
      'UI interface orientation': 'landscapeLeft',
      'Applied CL heading orientation': 'landscapeRight',
      'Filtered heading': '82.0°',
      'Kakao camera bearing · 마지막 snapshot': '15.0°',
      'Display heading · snapshot 기준': '67.0°',
    }.entries) {
      await tester.scrollUntilVisible(find.text(entry.key), 200);
      final tile = find.ancestor(of: find.text(entry.key), matching: find.byType(ListTile));
      expect(find.descendant(of: tile, matching: find.text(entry.value)), findsOneWidget);
    }
    expect(find.textContaining('latitude'), findsNothing);
    expect(find.textContaining('longitude'), findsNothing);
    expect(find.textContaining('do-not-expose-key'), findsNothing);
  });
}
