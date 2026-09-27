import 'package:destination_compass/core/compass/heading_provider.dart';
import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/destination/destination_model.dart';
import 'package:destination_compass/ui/compass_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget panel({Destination? destination, double progress = 0}) =>
      MaterialApp(home: Scaffold(body: Center(child: SizedBox(
        width: 400,
        height: progress == 0 ? 278 : 650,
        child: CompassPanel(
          progress: progress,
          destination: destination,
          distanceMeters: destination == null ? null : 2700,
          destinationBearing: destination == null ? null : 30,
          heading: const HeadingReading(degrees: 0, isTrueNorth: true),
          filteredHeading: 0,
          onClear: () {},
        ),
      ))));

  final destination = Destination(
    point: const GeoPoint(37.5, 127.0),
    name: '친구 집',
    createdAt: DateTime.utc(2026, 9, 27),
  );

  testWidgets('collapsed panel explains how to select a destination', (tester) async {
    await tester.pumpWidget(panel());
    expect(find.byKey(const Key('empty_destination')), findsOneWidget);
    expect(find.byKey(const Key('destination_arrow')), findsNothing);
  });

  testWidgets('collapsed panel shows destination, arrow, and distance', (tester) async {
    await tester.pumpWidget(panel(destination: destination));
    expect(find.text('친구 집'), findsOneWidget);
    expect(find.text('2.7 km'), findsOneWidget);
    expect(find.byKey(const Key('destination_arrow')), findsOneWidget);
  });

  testWidgets('expanded panel shows direction details and clear action', (tester) async {
    await tester.pumpWidget(panel(destination: destination, progress: 1));
    expect(find.textContaining('목적지 방향 30°'), findsOneWidget);
    expect(find.text('목적지 해제'), findsOneWidget);
  });
}
