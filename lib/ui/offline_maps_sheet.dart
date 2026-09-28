import 'dart:async';

import 'package:flutter/material.dart';

import '../core/geo_point.dart';
import '../offline/offline_map_controller.dart';
import '../offline/offline_region.dart';

class OfflineMapsSheet extends StatefulWidget {
  const OfflineMapsSheet({super.key, required this.controller,
    required this.currentPosition, required this.online});

  final OfflineMapController controller;
  final GeoPoint? currentPosition;
  final bool online;

  @override
  State<OfflineMapsSheet> createState() => _OfflineMapsSheetState();
}

class _OfflineMapsSheetState extends State<OfflineMapsSheet> {
  int radius = 20;
  bool estimating = false;
  String? message;

  OfflineRegion? get _draft => widget.currentPosition == null ? null
      : widget.controller.draft(widget.currentPosition!, radius);

  @override
  void initState() {
    super.initState();
    _estimate();
  }

  void _estimate() {
    final draft = _draft;
    if (draft == null || !widget.online || !widget.controller.configured) return;
    setState(() => estimating = true);
    unawaited(widget.controller.estimate(draft).whenComplete(() {
      if (mounted) setState(() => estimating = false);
    }));
  }

  Future<void> _download(OfflineRegion region) async {
    setState(() => message = null);
    try {
      await widget.controller.download(region);
      if (mounted) setState(() => message = '다운로드 완료');
    } catch (_) {
      if (mounted) setState(() => message = widget.controller.error);
    }
  }

  Future<void> _delete(OfflineRegion region) async {
    try {
      await widget.controller.delete(region);
    } catch (_) {
      if (mounted) setState(() => message = '지도 삭제에 실패했습니다. 다시 시도하세요.');
    }
  }

  static String size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: AnimatedBuilder(animation: widget.controller,
        builder: (context, _) {
          final maps = widget.controller;
          final draft = _draft;
          return ListView(shrinkWrap: true, padding: const EdgeInsets.all(20),
            children: [
              Text('오프라인 지도', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('다운로드 지역 데이터 합계 · ${size(maps.usageBytes)}'),
              const Text('공유 타일·Style Pack 때문에 기기 저장 공간 점유량과 다를 수 있습니다.',
                style: TextStyle(fontSize: 12)),
              if (!maps.configured) const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Mapbox 토큰이 없어 다운로드 기능이 비활성화되었습니다. '
                    '네이버 지도와 나침반은 계속 사용할 수 있습니다.')),
              if (draft == null) const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('현재 위치를 확인한 뒤 주변 지역을 다운로드할 수 있습니다.')),
              if (draft != null && maps.configured) ...[
                const SizedBox(height: 14),
                const Text('현재 위치 주변'),
                Wrap(spacing: 8, children: [for (final km in const [5, 20, 50])
                  ChoiceChip(label: Text('$km km'), selected: radius == km,
                    onSelected: (_) {
                      setState(() => radius = km);
                      _estimate();
                    }),
                ]),
                Text(estimating ? '예상 용량 계산 중…' :
                    maps.estimatedBytes == null ? '예상 용량을 알 수 없습니다.' :
                    '예상 다운로드 · 약 ${size(maps.estimatedBytes!)}'),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: widget.online && maps.downloadingId == null
                      ? () => _download(draft) : null,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(widget.online ? '다운로드' : '연결 복구 후 다운로드 가능')),
              ],
              if (maps.downloadingId != null) ...[
                const SizedBox(height: 14),
                Text('오프라인 지도 다운로드 · ${(maps.progress * 100).round()}%'),
                LinearProgressIndicator(value: maps.progress),
                Text('${size(maps.receivedBytes)} 수신'
                    '${maps.estimatedBytes == null ? '' : ' / 예상 ${size(maps.estimatedBytes!)}'}'),
              ],
              if (message != null) Padding(
                padding: const EdgeInsets.only(top: 8), child: Text(message!)),
              const Divider(height: 32),
              const Text('다운로드한 지역'),
              if (maps.regions.isEmpty) const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('아직 다운로드한 지역이 없습니다.')),
              for (final region in maps.regions)
                ListTile(contentPadding: EdgeInsets.zero,
                  title: Text(region.name, maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                  subtitle: Text(switch (region.status) {
                    OfflineRegionStatus.ready =>
                      '${size(region.sizeBytes)} · ${region.downloadedAt?.toLocal().toString().split(' ').first ?? ''} 다운로드',
                    OfflineRegionStatus.downloading => '다운로드 중',
                    OfflineRegionStatus.failed =>
                      region.failure ?? '다운로드 실패 · 재시도 가능',
                  }),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (region.status == OfflineRegionStatus.failed)
                      IconButton(tooltip: '다시 시도',
                        onPressed: widget.online && maps.downloadingId == null
                            ? () => _download(region) : null,
                        icon: const Icon(Icons.refresh)),
                    IconButton(tooltip: '지역 삭제',
                      onPressed: !maps.configured || maps.downloadingId == region.id
                          ? null : () => _delete(region),
                      icon: const Icon(Icons.delete_outline)),
                  ])),
            ]);
        }),
    )),
  );
}
