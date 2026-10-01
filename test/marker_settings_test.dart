import 'dart:async';
import 'package:destination_compass/settings/marker_settings.dart';
import 'package:destination_compass/ui/marker_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryMarkerStore implements MarkerSettingsStore {
  MarkerScales? saved;
  Completer<MarkerScales?>? pendingRead;
  bool failWrites = false;
  @override
  Future<MarkerScales?> read() async {
    if (pendingRead == null) return saved;
    return pendingRead!.future;
  }
  @override
  Future<void> write(MarkerScales value) async {
    if (failWrites) throw StateError('Unavailable');
    saved = value;
  }
}

void main() {
  test('independent defaults and reset', () async {
    final settings = MarkerSettingsController(MemoryMarkerStore());
    expect(settings.value.online, 1.25);
    expect(settings.value.offline, 1);
    await settings.setOnline(1.7);
    expect(settings.value.offline, 1);
    await settings.setOffline(0.8);
    expect(settings.value.online, 1.7);
    await settings.reset();
    expect(settings.value.online, 1.25);
    expect(settings.value.offline, 1);
    settings.dispose();
  });
  test('min max clamp finite fallback and default-compatible steps', () async {
    final settings = MarkerSettingsController(MemoryMarkerStore());
    await settings.setOnline(-20);
    await settings.setOffline(50);
    expect(settings.value.online, .5);
    expect(settings.value.offline, 2);
    await settings.setOnline(double.nan);
    expect(settings.value.online, 1.25);
    expect(MarkerScales.clamp(1.249, 1), 1.25);
    settings.dispose();
  });
  test('preferences persist both scales across controller restart', () async {
    SharedPreferences.setMockInitialValues({});
    final first = MarkerSettingsController(PreferencesMarkerSettingsStore());
    await first.setOnline(2);
    await first.setOffline(.5);
    first.dispose();
    final second = MarkerSettingsController(PreferencesMarkerSettingsStore());
    await second.restore();
    expect(second.value.online, 2);
    expect(second.value.offline, .5);
    second.dispose();
  });
  test('late restore cannot override live user edit', () async {
    final store = MemoryMarkerStore()..pendingRead = Completer<MarkerScales?>();
    final settings = MarkerSettingsController(store);
    final restoring = settings.restore();
    await settings.setOnline(1.5);
    store.pendingRead!.complete(const MarkerScales(online: .5));
    await restoring;
    expect(settings.value.online, 1.5);
    settings.dispose();
  });
  test('failed persistence retains live preview and permits retry', () async {
    final store = MemoryMarkerStore()..failWrites = true;
    final settings = MarkerSettingsController(store);
    await settings.setOnline(2);
    expect(settings.saveFailed, isTrue);
    expect(settings.value.online, 2);
    store.failWrites = false;
    await settings.setOnline(2);
    expect(settings.saveFailed, isFalse);
    expect(store.saved!.online, 2);
    settings.dispose();
  });
  test('Mapbox 100% geometry retained with independent 44px friend hit target', () {
    expect(MarkerScales.mapboxRadius('user', 1), 9);
    expect(MarkerScales.mapboxRadius('destination', 1), 11);
    for (final scale in [.5, 1.0, 1.25, 2.0]) {
      final visual = MarkerScales.mapboxRadius('member_f', scale);
      expect(MarkerScales.friendHitRadius(visual), greaterThanOrEqualTo(22));
    }
  });
  testWidgets('general settings preview, percentage labels and reset', (tester) async {
    final settings = MarkerSettingsController(MemoryMarkerStore());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MarkerSettingsSheet(controller: settings))));
    expect(find.text('현재: 125%'), findsOneWidget);
    expect(find.text('현재: 100%'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byKey(const ValueKey('online-marker-scale')));
    slider.onChanged!(1.5);
    await tester.pump();
    expect(find.text('현재: 150%'), findsOneWidget);
    expect(settings.value.offline, 1);
    await tester.tap(find.text('기본값으로 복원'));
    await tester.pump();
    expect(find.text('현재: 125%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });
}
