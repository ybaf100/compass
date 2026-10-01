import '../destination/bearing_engine.dart';

/// Clockwise degrees from screen-up. Native adapters use their current camera,
/// not a stale Flutter snapshot, while a camera gesture is in progress.
abstract final class MapUserHeading {
  static double? display(double? heading, double cameraBearing) =>
      heading == null || !heading.isFinite || !cameraBearing.isFinite
          ? null : BearingEngine.normalize(heading - cameraBearing);
}
