import 'package:flutter/material.dart';

class FullscreenCompassDetails extends StatelessWidget {
  const FullscreenCompassDetails({
    super.key,
    required this.progress,
    required this.bearing,
    required this.hasHeading,
    required this.isTrueNorth,
  });

  final double progress;
  final double? bearing;
  final bool hasHeading;
  final bool isTrueNorth;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: SizedBox(
      height: 58.0 * progress,
      child: Opacity(
        opacity: progress,
        child: Center(
          child: Text(
            !hasHeading
                ? '기기에서 방향 센서를 사용할 수 없습니다'
                : !isTrueNorth
                ? '자기북 기준 · 실제 방향에 차이가 있을 수 있습니다'
                : bearing == null
                ? '현재 위치를 확인하고 있습니다'
                : '목적지 방향 ${bearing!.round()}° · 기기 상단을 기준으로 보세요',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFA9C0D5), fontSize: 13),
          ),
        ),
      ),
    ),
  );
}
