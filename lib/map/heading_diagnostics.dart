import '../core/compass/heading_provider.dart';
import '../destination/bearing_engine.dart';
import 'map_user_heading.dart';

/// Service-sheet snapshot, never sent back to the native marker renderer.
/// Native rendering still compensates against its live camera exactly once.
class HeadingDiagnostics {
  const HeadingDiagnostics({this.interfaceOrientation, this.headingOrientation,
    this.filteredHeading, this.cameraBearing, this.displayHeading});

  factory HeadingDiagnostics.snapshot({HeadingReading? reading,
    double? filteredHeading, double? cameraBearing}) {
    double? finiteAngle(double? value) => value != null && value.isFinite
        ? BearingEngine.normalize(value) : null;
    final heading = finiteAngle(filteredHeading);
    final camera = finiteAngle(cameraBearing);
    return HeadingDiagnostics(
      interfaceOrientation: reading?.interfaceOrientation,
      headingOrientation: reading?.headingOrientation,
      filteredHeading: heading,
      cameraBearing: camera,
      displayHeading: camera == null ? null : MapUserHeading.display(heading, camera),
    );
  }

  final HeadingOrientation? interfaceOrientation;
  final HeadingOrientation? headingOrientation;
  final double? filteredHeading;
  final double? cameraBearing;
  final double? displayHeading;
}
