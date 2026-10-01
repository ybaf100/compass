import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only app-owned overlays are scaled, never either SDK's base-map POIs.
class MarkerScales {
  const MarkerScales({this.online = 1.25, this.offline = 1.0});
  static const minimum = 0.5;
  static const maximum = 2.0;
  static const divisions = 30; // 5% steps include the 125% default.
  final double online;
  final double offline;

  static double clamp(double value, double fallback) => value.isFinite
      ? (value.clamp(minimum, maximum) * 20).round() / 20 : fallback;

  /// Visual radius and tap radius are deliberately independent.
  static double mapboxRadius(String id, double scale) =>
      (id == 'user' ? 9 : 11) * clamp(scale, 1);
  static double friendHitRadius(double visualRadius) =>
      visualRadius < 22 ? 22 : visualRadius;
}

abstract interface class MarkerSettingsStore {
  Future<MarkerScales?> read();
  Future<void> write(MarkerScales value);
}

class PreferencesMarkerSettingsStore implements MarkerSettingsStore {
  static const key = 'map_marker_scales_v1';
  @override
  Future<MarkerScales?> read() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return MarkerScales(
      online: MarkerScales.clamp((json['onlineMarkerScale'] as num?)?.toDouble() ?? 1.25, 1.25),
      offline: MarkerScales.clamp((json['offlineMarkerScale'] as num?)?.toDouble() ?? 1, 1));
  }
  @override
  Future<void> write(MarkerScales value) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(key, jsonEncode({
      'onlineMarkerScale': value.online, 'offlineMarkerScale': value.offline}));
    if (!saved) throw StateError('Marker settings not saved');
  }
}

class MarkerSettingsController extends ChangeNotifier {
  MarkerSettingsController(this._store);
  final MarkerSettingsStore _store;
  MarkerScales _value = const MarkerScales();
  MarkerScales get value => _value;
  bool saveFailed = false;
  bool _disposed = false;
  int _revision = 0;
  Future<void> _writes = Future<void>.value();

  Future<void> restore() async {
    final revision = _revision;
    try {
      final saved = await _store.read();
      if (!_disposed && revision == _revision && saved != null) {
        _value = saved;
        notifyListeners();
      }
    } catch (_) {
      // Corrupt/unavailable preferences must not disable the map.
    }
  }

  Future<void> setOnline(double scale) => _set(MarkerScales(
      online: MarkerScales.clamp(scale, 1.25), offline: _value.offline));
  Future<void> setOffline(double scale) => _set(MarkerScales(
      online: _value.online, offline: MarkerScales.clamp(scale, 1)));
  Future<void> reset() => _set(const MarkerScales());

  Future<void> _set(MarkerScales next) {
    if (_disposed) return Future<void>.value();
    _revision++;
    _value = next;
    saveFailed = false;
    notifyListeners(); // Apply preview before asynchronous persistence.
    _writes = _writes.then((_) async {
      try {
        await _store.write(next);
      } catch (_) {
        if (!_disposed) { saveFailed = true; notifyListeners(); }
      }
    });
    return _writes;
  }

  @override
  void dispose() { _disposed = true; super.dispose(); }
}
