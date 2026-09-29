import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/map/map_mode_controller.dart';
import 'package:destination_compass/offline/offline_map_controller.dart';
import 'package:destination_compass/offline/offline_region.dart';
import 'package:destination_compass/offline/offline_region_repository.dart';
import 'package:destination_compass/offline/offline_tile_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Store implements OfflineRegionRepository {
  List<OfflineRegion> saved = [];
  @override
  Future<List<OfflineRegion>> load() async => List.of(saved);
  @override
  Future<void> save(List<OfflineRegion> regions) async => saved = List.of(regions);
}

class _Backend implements OfflineTileBackend {
  final ids = <String>{};
  int attempts = 0;
  bool fail = false;
  bool connected = true;
  @override
  Future<int?> estimate(OfflineRegion region) async => 12000000;
  @override
  Future<int> download(OfflineRegion region,
      void Function(double, int) onProgress) async {
    attempts++;
    onProgress(0.4, 4000);
    if (fail) throw StateError('storage full');
    ids.add(region.id);
    onProgress(1, 10000);
    return 10000;
  }
  @override
  Future<void> delete(String id) async { ids.remove(id); }
  @override
  Future<bool> exists(String id) async => ids.contains(id);
  @override
  Future<void> setConnected(bool value) async => connected = value;
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  const center = GeoPoint(37.52, 127.1);

  test('region circle coverage and persisted metadata survive restart', () async {
    final store = _Store(), backend = _Backend();
    final downloads = OfflineMapController(repository: store, backend: backend);
    await downloads.start();
    final draft = downloads.draft(center, 5, name: '송파구 주변');
    expect(draft.ring.length, 65);
    expect(draft.ring.first, draft.ring.last);
    expect(await downloads.estimate(draft), 12000000);
    await downloads.download(draft);
    expect(downloads.covering(center)?.id, draft.id);
    expect(downloads.covering(const GeoPoint(38, 127.1)), isNull);
    expect(downloads.progress, 1);
    expect(downloads.usageBytes, 10000);
    downloads.dispose();

    final restored = OfflineMapController(repository: store, backend: backend);
    await restored.start();
    expect(restored.covering(center)?.name, '송파구 주변');
    expect(restored.regions.single.downloadedAt, isNotNull);
    await restored.delete(restored.regions.single);
    expect(backend.ids, isEmpty);
    expect(store.saved, isEmpty);
    restored.dispose();
  });

  test('preferences repository round-trips region details', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = PreferencesOfflineRegionRepository();
    final region = OfflineRegion(id: 'r1', name: '송파구', center: center,
      radiusMeters: 20000, minZoom: 0, maxZoom: 15,
      downloadedAt: DateTime.utc(2026, 9, 28), sizeBytes: 12345678,
      status: OfflineRegionStatus.ready);
    await repository.save([region]);
    final restored = (await repository.load()).single;
    expect(restored.name, region.name);
    expect(restored.center, center);
    expect(restored.radiusMeters, 20000);
    expect(restored.maxZoom, 15);
    expect(restored.sizeBytes, 12345678);
    expect(restored.downloadedAt, region.downloadedAt);
    expect(restored.contains(center), isTrue);
  });

  test('missing Mapbox configuration never discards undeleted tile metadata', () async {
    final store = _Store();
    final offline = OfflineMapController(repository: store, backend: null);
    final region = offline.draft(center, 5);
    store.saved = [region];
    await offline.start();
    await expectLater(offline.delete(region), throwsStateError);
    expect(offline.regions.single.id, region.id);
    expect(store.saved.single.id, region.id);
    offline.dispose();
  });

  test('failed download stays retryable and interrupted download never covers', () async {
    final store = _Store(), backend = _Backend()..fail = true;
    final downloads = OfflineMapController(repository: store, backend: backend);
    await downloads.start();
    final draft = downloads.draft(center, 20);
    await expectLater(downloads.download(draft), throwsStateError);
    expect(downloads.regions.single.status, OfflineRegionStatus.failed);
    expect(downloads.covering(center), isNull);
    backend.fail = false;
    await downloads.download(downloads.regions.single);
    expect(downloads.covering(center), isNotNull);
    expect(backend.attempts, 2);
    store.saved = [draft.copyWith(status: OfflineRegionStatus.downloading)];
    final restarted = OfflineMapController(repository: store, backend: backend);
    await restarted.start();
    expect(restarted.regions.single.status, OfflineRegionStatus.failed);
    restarted.dispose(); downloads.dispose();
  });

  test('online/offline/no coverage recovery and hysteresis', () async {
    final store = _Store(), backend = _Backend();
    final downloads = OfflineMapController(repository: store, backend: backend);
    await downloads.start();
    await downloads.download(downloads.draft(center, 5));
    final mode = MapModeController(kakaoConfigured: true,
      offlineMaps: downloads, switchDelay: const Duration(milliseconds: 1),
      recoveryDelay: const Duration(milliseconds: 1));
    mode.update(connected: false, position: center);
    await settle();
    expect(mode.mode, MapMode.offlineMapbox);
    mode.update(connected: true);
    await settle();
    expect(mode.mode, MapMode.onlineKakao);
    mode.kakaoFailure();
    await settle();
    expect(mode.mode, MapMode.offlineMapbox);
    mode.update(position: const GeoPoint(38, 128));
    await settle();
    expect(mode.mode, MapMode.mapUnavailable);
    mode.retryKakao();
    await settle();
    expect(mode.mode, MapMode.onlineKakao);
    mode.dispose(); downloads.dispose();
  });

  test('short connectivity flaps do not switch the active provider', () async {
    final downloads = OfflineMapController(repository: _Store(),
      backend: _Backend());
    await downloads.start();
    await downloads.download(downloads.draft(center, 5));
    final mode = MapModeController(kakaoConfigured: true,
      offlineMaps: downloads, switchDelay: const Duration(milliseconds: 40),
      recoveryDelay: const Duration(milliseconds: 40));
    mode.update(connected: false, position: center);
    mode.update(connected: true);
    await Future<void>.delayed(const Duration(milliseconds: 55));
    expect(mode.mode, MapMode.onlineKakao);
    mode.dispose(); downloads.dispose();
  });
}
