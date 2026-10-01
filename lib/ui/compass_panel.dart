import 'package:flutter/material.dart';

import '../destination/bearing_engine.dart';
import '../destination/destination_model.dart';
import 'compass_arrow.dart';

/// One presentation policy throughout the existing gesture: arrow + distance.
class CompassPanel extends StatelessWidget {
  const CompassPanel({super.key, required this.progress,
    required this.destination, required this.distanceMeters,
    required this.destinationBearing, required this.filteredHeading});

  final double progress;
  final Destination? destination;
  final double? distanceMeters;
  final double? destinationBearing;
  final double? filteredHeading;

  static String formatDistance(double? meters) {
    if (meters == null) return '현재 위치를 확인하고 있습니다';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final expanded = progress.clamp(0.0, 1.0).toDouble();
    return LayoutBuilder(builder: (context, constraints) {
      // No content/size breakpoint during a swipe, including short landscape.
      final spacing = 12.0 + 20.0 * expanded;
      final textHeight = destination == null ? 44.0 : (22.0 + 16.0 * expanded) * 1.5;
      final errorHeight = destination != null && filteredHeading == null ? 26.0 : 0.0;
      final available = (constraints.maxHeight - 28 - spacing - textHeight - errorHeight)
          .clamp(0.0, constraints.maxHeight).toDouble();
      final arrowSize = (108.0 + 152.0 * expanded).clamp(0.0, available).toDouble();
      final relative = destinationBearing != null && filteredHeading != null
          ? BearingEngine.relativeAngle(destinationBearing!, filteredHeading!)
          : null;
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Center(child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(children: [
            const SizedBox(height: 11),
            Container(key: const Key('compass_handle'), width: 48, height: 5,
              decoration: BoxDecoration(color: const Color(0xFF7188A2),
                borderRadius: BorderRadius.circular(5))),
            Expanded(child: Center(child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedSwitcher(duration: const Duration(milliseconds: 240),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation, child: ScaleTransition(
                      scale: Tween(begin: 0.92, end: 1.0).animate(animation), child: child)),
                  child: destination == null
                      ? Icon(Icons.explore_outlined, key: const Key('empty_compass_icon'),
                          size: arrowSize, color: const Color(0xFF6F90AA))
                      : CompassArrow(key: const Key('destination_arrow'),
                          relativeAngle: relative, size: arrowSize)),
                SizedBox(height: spacing),
                AnimatedSwitcher(duration: const Duration(milliseconds: 240),
                  child: destination == null
                      ? const Text('지도에서 목적지를 선택하세요',
                          key: Key('empty_destination'), textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 17,
                            fontWeight: FontWeight.w600))
                      : Text(distanceMeters == null ? '—' : formatDistance(distanceMeters),
                          key: const Key('destination_distance'), textAlign: TextAlign.center,
                          style: TextStyle(color: const Color(0xFF69E1F5),
                            fontSize: 22.0 + 16.0 * expanded, fontWeight: FontWeight.w700))),
                if (destination != null && filteredHeading == null)
                  const Padding(padding: EdgeInsets.only(top: 8),
                    child: Text('방향 센서 사용 불가', key: Key('compass_sensor_unavailable'),
                      style: TextStyle(color: Color(0xFFFFC790), fontSize: 12))),
              ])))),
            const SizedBox(height: 12),
          ]))),
      );
    });
  }
}
