import 'package:destination_compass/core/geo_point.dart';
import 'package:destination_compass/map/map_mode_controller.dart';
import 'package:destination_compass/offline/offline_map_controller.dart';
import 'package:destination_compass/offline/offline_region.dart';
import 'package:destination_compass/offline/offline_region_repository.dart';
import 'package:destination_compass/offline/offline_tile_backend.dart';
import 'package:flutter_test/flutter_test.dart';

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
    final mode = MapModeController(naverConfigured: true,
      offlineMaps: downloads, switchDelay: const Duration(milliseconds: 1),
      recoveryDelay: const Duration(milliseconds: 1));
    mode.update(connected: false, position: center);
    await settle();
    expect(mode.mode, MapMode.offlineMapbox);
    mode.update(connected: true);
    await settle();
    expect(mode.mode, MapMode.onlineNaver);
    mode.naverFailure();
    await settle();
    expect(mode.mode, MapMode.offlineMapbox);
    mode.update(position: const GeoPoint(38, 128));
    await settle();
    expect(mode.mode, MapMode.mapUnavailable);
    mode.retryNaver();
    await settle();
    expect(mode.mode, MapMode.onlineNaver);
    mode.dispose(); downloads.dispose();
  });
}
