import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'offline_region.dart';

abstract class OfflineRegionRepository {
  Future<List<OfflineRegion>> load();
  Future<void> save(List<OfflineRegion> regions);
}

class PreferencesOfflineRegionRepository implements OfflineRegionRepository {
  static const key = 'offline_regions_v1';

  @override
  Future<List<OfflineRegion>> load() async {
    final encoded = (await SharedPreferences.getInstance()).getString(key);
    if (encoded == null) return const [];
    try {
      return [for (final value in jsonDecode(encoded) as List)
        if (value is Map<String, dynamic>)
          ?OfflineRegion.fromJson(value)].whereType<OfflineRegion>().toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<OfflineRegion> regions) async {
    final saved = await (await SharedPreferences.getInstance()).setString(
      key, jsonEncode(regions.map((region) => region.toJson()).toList()));
    if (!saved) throw StateError('오프라인 지도 목록을 저장하지 못했습니다.');
  }
}
