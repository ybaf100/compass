/// Whitelisted diagnostics only; orientation conversion is owned by iOS.
enum HeadingOrientation {
  unknown, portrait, portraitUpsideDown, landscapeLeft, landscapeRight;

  static HeadingOrientation? decode(Object? value) {
    for (final orientation in values) {
      if (orientation.name == value) return orientation;
    }
    return null;
  }
}

class HeadingReading {
  const HeadingReading({
    required this.degrees,
    required this.isTrueNorth,
    this.accuracyDegrees,
    this.interfaceOrientation,
    this.headingOrientation,
  });

  final double degrees;
  final bool isTrueNorth;
  final double? accuracyDegrees;
  final HeadingOrientation? interfaceOrientation;
  final HeadingOrientation? headingOrientation;
}

abstract class HeadingProvider {
  Stream<HeadingReading?> get heading;

  /// Supplies the last GPS fix for magnetic-declination correction on Android.
  Future<void> updateLocation(double latitude, double longitude, double altitude);
}
