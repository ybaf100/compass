import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/destination/destination_model.dart';
import 'package:destination_compass/ui/compass_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget panel({Destination? destination, double progress = 0,
      double? heading = 0, double? distance = 2700, double? height}) =>
      MaterialApp(home: Scaffold(body: Center(child: SizedBox(
        width: 400,
        height: height ?? (progress == 0 ? 278 : 550),
        child: CompassPanel(
          progress: progress,
          destination: destination,
          distanceMeters: destination == null ? null : distance,
          destinationBearing: destination == null ? null : 30,
          filteredHeading: heading,
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

  testWidgets('collapsed panel shows only arrow and distance', (tester) async {
    await tester.pumpWidget(panel(destination: destination));
    expect(find.text('친구 집'), findsNothing);
    expect(find.text('2.7 km'), findsOneWidget);
    expect(find.byKey(const Key('destination_arrow')), findsOneWidget);
  });

  testWidgets('expanded panel keeps arrow and distance without details or clear action', (tester) async {
    await tester.pumpWidget(panel(destination: destination, progress: 1));
    expect(find.text('2.7 km'), findsOneWidget);
    expect(find.byKey(const Key('destination_arrow')), findsOneWidget);
    expect(find.textContaining('목적지 방향'), findsNothing);
    expect(find.text('목적지 해제'), findsNothing);
    expect(find.text('친구 집'), findsNothing);
  });

  for (final progress in [0.0, 0.25, 0.5, 0.75, 1.0]) {
    testWidgets('progress $progress never reveals mode, notice, north or controls', (tester) async {
      await tester.pumpWidget(panel(destination: destination, progress: progress));
      expect(find.byType(Text), findsOneWidget);
      expect(find.text('2.7 km'), findsOneWidget);
      expect(find.text('친구 집'), findsNothing);
      expect(find.byKey(const Key('navigation_mode')), findsNothing);
      for (final text in ['내 목적지', '모두의 목적지', '친구 따라가기', '내 목적지로 전환',
          '목적지 해제', '자기북 기준', '오래된 위치', '마지막 위치 기준', '30°']) {
        expect(find.textContaining(text), findsNothing);
      }
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing sensor permits only a minimal error, retaining distance', (tester) async {
    await tester.pumpWidget(panel(destination: destination, progress: 1, heading: null));
    expect(find.text('방향 센서 사용 불가'), findsOneWidget);
    expect(find.text('2.7 km'), findsOneWidget);
    expect(find.text('친구 집'), findsNothing);
  });

  testWidgets('unknown distance uses a placeholder without extra descriptions', (tester) async {
    await tester.pumpWidget(panel(destination: destination, distance: null));
    expect(find.text('—'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('short landscape and tablet widths do not overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final progress in [0.0, 0.5, 1.0]) {
      await tester.pumpWidget(panel(destination: destination, progress: progress, height: 174));
      expect(find.text('2.7 km'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
