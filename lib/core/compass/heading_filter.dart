import '../../destination/bearing_engine.dart';

/// Circular low-pass filter: quiet readings are damped, deliberate turns catch up.
class HeadingFilter {
  double? _value;

  double? get value => _value;

  double update(double rawDegrees) {
    final raw = BearingEngine.normalize(rawDegrees);
    final previous = _value;
    if (previous == null) return _value = raw;
    final delta = BearingEngine.shortestDelta(previous, raw);
    if (delta.abs() < 0.8) return previous;
    final gain = delta.abs() > 25 ? 0.55 : delta.abs() > 7 ? 0.35 : 0.18;
    return _value = BearingEngine.normalize(previous + delta * gain);
  }

  void reset() => _value = null;
}
