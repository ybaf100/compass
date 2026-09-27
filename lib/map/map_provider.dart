import 'package:flutter/widgets.dart';

import '../core/geo_point.dart';
import '../core/location/location_provider.dart';
import '../destination/destination_model.dart';

/// UI and destination math depend on this contract, never on a map SDK type.
abstract class MapProvider {
  Widget buildMap({
    required double bottomPadding,
    required ValueChanged<GeoPoint> onPicked,
    required void Function(GeoPoint, String) onNamedPlacePicked,
    required VoidCallback onLoaded,
    required VoidCallback onGesture,
  });

  Future<void> moveCamera(GeoPoint point, {double? zoom});
  Future<void> setDestination(Destination? destination);
  void setPinReveal(double progress);
  Future<void> setCandidate(GeoPoint? candidate);
  Future<void> setUserLocation(LocationFix? location, {required bool follow});
  void reset();
  void dispose();
}
