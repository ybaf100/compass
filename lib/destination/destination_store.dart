import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'destination_model.dart';

abstract class DestinationStore {
  Future<Destination?> load();
  Future<void> save(Destination? destination);
}

class PreferencesDestinationStore implements DestinationStore {
  PreferencesDestinationStore([SharedPreferencesAsync? preferences])
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'last_destination_v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<Destination?> load() async {
    try {
      final raw = await _preferences.getString(_key);
      if (raw == null) return null;
      final data = jsonDecode(raw);
      return data is Map<String, dynamic> ? Destination.fromJson(data) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Destination? destination) async {
    if (destination == null) {
      await _preferences.remove(_key);
    } else {
      await _preferences.setString(_key, jsonEncode(destination.toJson()));
    }
  }
}
