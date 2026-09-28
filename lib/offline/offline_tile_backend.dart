import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mb;

import 'offline_region.dart';

abstract class OfflineTileBackend {
  Future<int?> estimate(OfflineRegion region);
  Future<int> download(OfflineRegion region,
      void Function(double fraction, int bytes) onProgress);
  Future<void> delete(String id);
  Future<bool> exists(String id);
  Future<void> setConnected(bool connected);
}

/// Mapbox's official StylePack + TileStore APIs; never downloads raw tiles.
class MapboxTileBackend implements OfflineTileBackend {
  static const styleUri = mb.MapboxStyles.MAPBOX_STREETS;
  mb.TileStore? _tileStore;
  mb.OfflineManager? _offlineManager;

  Future<mb.TileStore> get _tiles async =>
      _tileStore ??= await mb.TileStore.createDefault();
  Future<mb.OfflineManager> get _styles async =>
      _offlineManager ??= await mb.OfflineManager.create();

  mb.TileRegionLoadOptions _options(OfflineRegion region) =>
      mb.TileRegionLoadOptions(
        geometry: mb.Polygon(coordinates: [
          region.ring.map((pair) => mb.Position(pair[0], pair[1])).toList(),
        ]).toJson(),
        descriptorsOptions: [mb.TilesetDescriptorOptions(
          styleURI: styleUri, minZoom: region.minZoom,
          maxZoom: region.maxZoom,
        )],
        acceptExpired: true,
        networkRestriction: mb.NetworkRestriction.NONE,
      );

  @override
  Future<int?> estimate(OfflineRegion region) async {
    final result = await (await _tiles).estimateTileRegion(region.id,
      _options(region), mb.TileRegionEstimateOptions(errorMargin: 0.15,
          preciseEstimationTimeout: 5, timeout: 12), null);
    return result.storageSize;
  }

  @override
  Future<int> download(OfflineRegion region,
      void Function(double, int) onProgress) async {
    final styles = await _styles;
    var styleBytes = 0;
    final style = await styles.loadStylePack(styleUri, mb.StylePackLoadOptions(
      glyphsRasterizationMode:
          mb.GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
      metadata: {'app': 'destination-compass'}, acceptExpired: false,
    ), (progress) {
      styleBytes = progress.completedResourceSize;
      final total = progress.requiredResourceCount;
      onProgress(total == 0 ? 0 : 0.12 * progress.completedResourceCount / total,
          styleBytes);
    });
    final result = await (await _tiles).loadTileRegion(region.id,
        _options(region), (progress) {
      final total = progress.requiredResourceCount;
      onProgress(total == 0 ? 0.12 : 0.12 +
          0.88 * progress.completedResourceCount / total,
          styleBytes + progress.completedResourceSize);
    });
    final size = style.completedResourceSize + result.completedResourceSize;
    onProgress(1, size);
    return result.completedResourceSize;
  }

  @override
  Future<void> delete(String id) async {
    await (await _tiles).removeRegion(id);
    // STREETS style pack is shared by every region; never evict it here.
  }

  @override
  Future<bool> exists(String id) async =>
      (await (await _tiles).allTileRegions()).any((region) => region.id == id);

  @override
  Future<void> setConnected(bool connected) =>
      mb.OfflineSwitch.shared.setMapboxStackConnected(connected);
}
