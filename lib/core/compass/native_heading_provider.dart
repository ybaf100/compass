import 'package:flutter/services.dart';

import '../../destination/bearing_engine.dart';
import 'heading_provider.dart';

class NativeHeadingProvider implements HeadingProvider {
  static const _events = EventChannel('app.destination_compass/heading');
  static const _control = MethodChannel('app.destination_compass/heading_control');

  @override
  Stream<HeadingReading?> get heading => _events.receiveBroadcastStream().map(
    (value) {
      if (value is! Map) return null;
      final degrees = value['heading'];
      if (degrees is! num || !degrees.toDouble().isFinite) return null;
      final accuracy = value['accuracy'];
      return HeadingReading(
        degrees: BearingEngine.normalize(degrees.toDouble()),
        isTrueNorth: value['trueNorth'] == true,
        accuracyDegrees: accuracy is num ? accuracy.toDouble() : null,
      );
    },
  );

  @override
  Future<void> updateLocation(
    double latitude,
    double longitude,
    double altitude,
  ) async {
    await _control.invokeMethod<void>('updateLocation', {
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
    });
  }
}
