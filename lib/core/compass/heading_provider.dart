class HeadingReading {
  const HeadingReading({
    required this.degrees,
    required this.isTrueNorth,
    this.accuracyDegrees,
  });

  final double degrees;
  final bool isTrueNorth;
  final double? accuracyDegrees;
}

abstract class HeadingProvider {
  Stream<HeadingReading?> get heading;

  /// Supplies the last GPS fix for magnetic-declination correction on Android.
  Future<void> updateLocation(double latitude, double longitude, double altitude);
}
