import 'package:flutter/foundation.dart';

import '../core/geo_point.dart';
import 'offline_region.dart';
import 'offline_region_repository.dart';
import 'offline_tile_backend.dart';

/// Owns user downloads; location/sensor/room lifecycles do not depend on it.
class OfflineMapController extends ChangeNotifier {
  OfflineMapController({required OfflineRegionRepository repository,
    required OfflineTileBackend? backend}) : _repository = repository,
      _backend = backend;

  final OfflineRegionRepository _repository;
  final OfflineTileBackend? _backend;
  List<OfflineRegion> regions = const [];
  String? error;
  bool loading = true;
  String? downloadingId;
  double progress = 0;
  int receivedBytes = 0;
  int? estimatedBytes;
  int _estimateGeneration = 0;
  bool _disposed = false;

  bool get configured => _backend != null;
  Future<void> setMapboxConnected(bool connected) async {
    await _backend?.setConnected(connected);
  }
  int get usageBytes => regions.where((r) => r.status == OfflineRegionStatus.ready)
      .fold(0, (total, region) => total + region.sizeBytes);

  OfflineRegion? covering(GeoPoint? point) {
    if (point == null) return null;
    for (final region in regions) {
      if (region.contains(point)) return region;
    }
    return null;
  }

  Future<void> start() async {
    try {
      regions = [for (final region in await _repository.load())
        if (region.status == OfflineRegionStatus.downloading)
          region.copyWith(status: OfflineRegionStatus.failed,
            failure: '이전 다운로드가 중단되었습니다. 다시 시도하세요.')
        else region];
      if (_backend != null) {
        // Metadata can outlive native tiles (e.g. an OS storage cleanup).
        final verified = <OfflineRegion>[];
        for (final region in regions) {
          if (region.status != OfflineRegionStatus.ready) {
            verified.add(region);
            continue;
          }
          try {
            verified.add(await _backend.exists(region.id) ? region :
                region.copyWith(status: OfflineRegionStatus.failed,
                    failure: '저장된 지도 파일이 없습니다. 다시 다운로드하세요.'));
          } catch (_) {
            verified.add(region.copyWith(status: OfflineRegionStatus.failed,
                failure: '저장된 지도를 확인할 수 없습니다.'));
          }
        }
        regions = verified;
        await _repository.save(regions);
      }
    } catch (_) {
      error = '오프라인 지도 목록을 읽을 수 없습니다.';
    } finally {
      loading = false;
      _notify();
    }
  }

  OfflineRegion draft(GeoPoint center, int kilometers, {String? name}) {
    if (!center.isValid || !const [5, 20, 50].contains(kilometers)) {
      throw ArgumentError('유효한 중심과 반경이 필요합니다.');
    }
    final latitude = center.latitude.toStringAsFixed(4).replaceAll('.', '_');
    final longitude = center.longitude.toStringAsFixed(4).replaceAll('.', '_');
    return OfflineRegion(id: 'region_${latitude}_${longitude}_$kilometers',
      name: name ?? '${center.label} 주변 $kilometers km',
      center: center, radiusMeters: kilometers * 1000.0,
      minZoom: 0, maxZoom: 15, status: OfflineRegionStatus.failed);
  }

  Future<int?> estimate(OfflineRegion region) async {
    final backend = _backend;
    final generation = ++_estimateGeneration;
    estimatedBytes = null;
    error = null;
    _notify();
    if (backend == null) return null;
    try {
      final bytes = await backend.estimate(region);
      if (generation == _estimateGeneration && !_disposed) {
        estimatedBytes = bytes;
        _notify();
      }
      return bytes;
    } catch (_) {
      // An estimate is advisory and never blocks a download.
      if (generation == _estimateGeneration && !_disposed) _notify();
      return null;
    }
  }

  Future<void> download(OfflineRegion region) async {
    final backend = _backend;
    if (backend == null) throw StateError('Mapbox access token이 필요합니다.');
    if (downloadingId != null) throw StateError('다른 지역을 다운로드 중입니다.');
    downloadingId = region.id;
    progress = 0;
    receivedBytes = 0;
    error = null;
    _replace(region.copyWith(status: OfflineRegionStatus.downloading));
    try {
      await _repository.save(regions);
      final size = await backend.download(region, (fraction, bytes) {
        progress = fraction.clamp(0.0, 1.0).toDouble();
        receivedBytes = bytes;
        _notify();
      });
      _replace(region.copyWith(status: OfflineRegionStatus.ready,
          downloadedAt: DateTime.now().toUtc(), sizeBytes: size));
      await _repository.save(regions);
    } catch (exception) {
      error = '다운로드에 실패했습니다. 연결 또는 저장 공간을 확인하고 재시도하세요.';
      _replace(region.copyWith(status: OfflineRegionStatus.failed,
          failure: error));
      await _repository.save(regions);
      rethrow;
    } finally {
      downloadingId = null;
      _notify();
    }
  }

  Future<void> delete(OfflineRegion region) async {
    if (downloadingId == region.id) throw StateError('다운로드 중에는 삭제할 수 없습니다.');
    final backend = _backend;
    if (backend == null) {
      throw StateError('Mapbox 설정 후 저장된 지도를 삭제할 수 있습니다.');
    }
    if (await backend.exists(region.id)) {
      await backend.delete(region.id);
    }
    regions = regions.where((item) => item.id != region.id).toList();
    _notify();
    await _repository.save(regions);
  }

  void _replace(OfflineRegion value) {
    regions = [for (final existing in regions)
      if (existing.id != value.id) existing, value];
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
