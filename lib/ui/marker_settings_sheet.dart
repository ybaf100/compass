import 'dart:async';
import 'package:flutter/material.dart';
import '../settings/marker_settings.dart';

class MarkerSettingsSheet extends StatelessWidget {
  const MarkerSettingsSheet({super.key, required this.controller});
  final MarkerSettingsController controller;

  @override
  Widget build(BuildContext context) => SafeArea(child: Center(
    heightFactor: 1,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 540),
      child: AnimatedBuilder(animation: controller, builder: (context, _) =>
        SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('지도 마커 크기', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 18),
            _slider('온라인 지도 · Kakao', 'online-marker-scale',
                controller.value.online, controller.setOnline),
            _slider('오프라인 지도 · Mapbox', 'offline-marker-scale',
                controller.value.offline, controller.setOffline),
            TextButton(onPressed: () => unawaited(controller.reset()),
              child: const Text('기본값으로 복원')),
            if (controller.saveFailed) const Text('설정을 저장하지 못했습니다. 다시 시도하세요.'),
          ])),
        )),
    )));

  Widget _slider(String label, String key, double value,
      Future<void> Function(double) onChanged) => Column(children: [
    Row(children: [Expanded(child: Text(label)), Text('현재: ${(value * 100).round()}%')]),
    Row(children: [const Text('50%'), Expanded(child: Slider(
      key: ValueKey(key), min: MarkerScales.minimum, max: MarkerScales.maximum,
      divisions: MarkerScales.divisions, value: value,
      label: '${(value * 100).round()}%',
      onChanged: (value) => unawaited(onChanged(value)))), const Text('200%')]),
  ]);
}
