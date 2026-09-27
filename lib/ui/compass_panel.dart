import 'package:flutter/material.dart';

import '../core/compass/heading_provider.dart';
import '../destination/bearing_engine.dart';
import '../destination/destination_model.dart';
import 'compass_arrow.dart';
import 'fullscreen_compass.dart';

class CompassPanel extends StatelessWidget {
  const CompassPanel({
    super.key,
    required this.progress,
    required this.destination,
    required this.distanceMeters,
    required this.destinationBearing,
    required this.heading,
    required this.filteredHeading,
    required this.onClear,
    this.modeLabel,
    this.notice,
    this.emptyMessage,
    this.clearLabel = '목적지 해제',
  });

  final double progress;
  final Destination? destination;
  final double? distanceMeters;
  final double? destinationBearing;
  final HeadingReading? heading;
  final double? filteredHeading;
  final VoidCallback onClear;
  final String? modeLabel;
  final String? notice;
  final String? emptyMessage;
  final String clearLabel;

  static String formatDistance(double? meters) {
    if (meters == null) return '현재 위치를 확인하고 있습니다';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  @override
  Widget build(BuildContext context) {
    final expanded = progress.clamp(0.0, 1.0).toDouble();
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxHeight < 210;
      final arrowSize = (compact ? 70.0 : 108.0) +
          ((constraints.maxHeight * 0.33).clamp(126.0, 240.0).toDouble() -
              (compact ? 70.0 : 108.0)) * expanded;
      final relative = destinationBearing != null && filteredHeading != null
          ? BearingEngine.relativeAngle(
              destinationBearing!, filteredHeading!)
          : null;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              children: [
                const SizedBox(height: 11),
                Container(
                  key: const Key('compass_handle'),
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7188A2),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 8),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween(begin: 0.92, end: 1.0)
                                        .animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: destination == null
                                ? Icon(
                                    Icons.explore_outlined,
                                    key: const Key('empty_compass_icon'),
                                    size: arrowSize,
                                    color: const Color(0xFF6F90AA),
                                  )
                                : CompassArrow(
                                    key: const Key('destination_arrow'),
                                    relativeAngle: relative,
                                    size: arrowSize,
                                  ),
                          ),
                          SizedBox(height: compact ? 8.0 : 12.0 + 20.0 * expanded),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            child: destination == null
                                ? Text(
                                    emptyMessage ?? '지도에서 목적지를 선택하세요',
                                    key: const Key('empty_destination'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  )
                                : Text(
                                    destination!.title,
                                    key: const Key('destination_title'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: compact ? 16.0 : 20.0 + 7.0 * expanded,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                          if (destination != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              formatDistance(distanceMeters),
                              key: const Key('destination_distance'),
                              style: TextStyle(
                                color: const Color(0xFF69E1F5),
                                fontSize: compact ? 17.0 : 22.0 + 10.0 * expanded,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (modeLabel != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: Text(modeLabel!, key: const Key('navigation_mode'),
                                  style: const TextStyle(color: Color(0xFFB4CDD9),
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                            if (notice != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(notice!, textAlign: TextAlign.center,
                                  style: const TextStyle(color: Color(0xFFFFC790),
                                    fontSize: 12)),
                              ),
                            if ((heading?.isTrueNorth != true) && !compact)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  heading == null ? '방향 센서 사용 불가' : '자기북 기준 · 방향 오차 가능',
                                  style: const TextStyle(color: Color(0xFFFFC790)),
                                ),
                              ),
                            FullscreenCompassDetails(
                              progress: expanded,
                              bearing: destinationBearing,
                              hasHeading: heading != null,
                              isTrueNorth: heading?.isTrueNorth ?? false,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (destination != null && expanded > 0.6)
                  Opacity(
                    opacity: ((expanded - 0.6) / 0.4).clamp(0.0, 1.0).toDouble(),
                    child: TextButton.icon(
                      onPressed: onClear,
                      icon: const Icon(Icons.close),
                      label: Text(clearLabel),
                    ),
                  ),
                SizedBox(height: compact ? 5.0 : 12.0),
              ],
            ),
          ),
        ),
      );
    });
  }
}
