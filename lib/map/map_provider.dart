import 'package:flutter/widgets.dart';

import '../core/geo_point.dart';
import '../core/location/location_provider.dart';
import '../destination/destination_model.dart';

class MapMemberOverlay {
  const MapMemberOverlay({required this.id, required this.name,
    required this.point, required this.updatedAt, required this.isStale});
  final String id;
  final String name;
  final GeoPoint point;
  final DateTime updatedAt;
  final bool isStale;

  MapMemberOverlay at(GeoPoint position) => MapMemberOverlay(
    id: id, name: name, point: position,
    updatedAt: updatedAt, isStale: isStale,
  );
}

class MapPingOverlay {
  const MapPingOverlay({required this.id, required this.point,
    required this.label});
  final String id;
  final GeoPoint point;
  final String label;
}

/// UI and destination math depend on this contract, never on a map SDK type.
abstract class MapProvider {
  Widget buildMap({
    required double bottomPadding,
    required ValueChanged<GeoPoint> onPicked,
    required void Function(GeoPoint, String) onNamedPlacePicked,
    required VoidCallback onLoaded,
    required VoidCallback onGesture,
    void Function(String memberId)? onMemberTapped,
  });

  Future<void> moveCamera(GeoPoint point, {double? zoom});
  Future<void> setDestination(Destination? destination);
  void setPinReveal(double progress);
  Future<void> setCandidate(GeoPoint? candidate);
  Future<void> setUserLocation(LocationFix? location, {required bool follow});
  Future<void> setMembers(List<MapMemberOverlay> members);
  Future<void> setSharedPings(List<MapPingOverlay> pings);
  void reset();
  void dispose();
}
