import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/geo_point.dart';
import '../destination/destination_controller.dart';
import '../map/map_provider.dart';
import 'compass_panel.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.controller,
    required this.mapProvider,
    required this.mapConfigured,
    required this.mapError,
  });

  final DestinationController controller;
  final MapProvider mapProvider;
  final bool mapConfigured;
  final ValueListenable<String?> mapError;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _expansion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final AnimationController _pinReveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  )..addListener(() => widget.mapProvider.setPinReveal(_pinReveal.value));
  late final Listenable _headingChanges = Listenable.merge([
    widget.controller.heading,
    widget.controller.filteredHeading,
  ]);

  Timer? _mapTimeout;
  int _mapGeneration = 0;
  bool _mapLoaded = false;
  bool _mapTimedOut = false;
  bool _following = true;
  GeoPoint? _lastDestinationPoint;
  String? _mapOperationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerChanged);
    if (widget.mapConfigured) _armMapTimeout();
    unawaited(widget.controller.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.onAppResume());
    }
  }

  void _onControllerChanged() {
    final point = widget.controller.destination?.point;
    if (point != null && point != _lastDestinationPoint) {
      _pinReveal.forward(from: 0.15);
    }
    _lastDestinationPoint = point;
    _runMap(widget.mapProvider.setDestination(widget.controller.destination));
    _runMap(widget.mapProvider.setCandidate(widget.controller.selectedPoint));
    _runMap(widget.mapProvider.setUserLocation(
      widget.controller.location,
      follow: _following,
    ));
    if (mounted) setState(() {});
  }

  void _runMap(Future<void> operation) {
    unawaited(operation.catchError((Object error) {
      if (mounted) setState(() => _mapOperationError = '지도를 조작할 수 없습니다. 다시 시도하세요.');
    }));
  }

  void _armMapTimeout() {
    _mapTimeout?.cancel();
    _mapTimeout = Timer(const Duration(seconds: 18), () {
      if (mounted && !_mapLoaded) setState(() => _mapTimedOut = true);
    });
  }

  void _retryMap() {
    widget.mapProvider.reset();
    setState(() {
      _mapGeneration++;
      _mapLoaded = false;
      _mapTimedOut = false;
      _mapOperationError = null;
    });
    _armMapTimeout();
  }

  void _recenter() {
    final point = widget.controller.location?.point;
    if (point == null) {
      unawaited(widget.controller.refreshLocation(requestPermission: true));
      return;
    }
    setState(() => _following = true);
    _runMap(widget.mapProvider.moveCamera(point, zoom: 16));
  }

  @override
  void dispose() {
    _mapTimeout?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onControllerChanged);
    _expansion.dispose();
    _pinReveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(builder: (context, constraints) {
        final height = constraints.maxHeight;
        final collapsed = height < 450 ? 174.0 : 278.0;
        final travel = (height - collapsed).clamp(1.0, double.infinity).toDouble();
        return Stack(children: [
          Positioned.fill(child: _buildMap(collapsed)),
          Positioned(
            left: 16,
            right: 16,
            top: 12,
            child: _buildHeader(),
          ),
          if (widget.controller.selectedPoint != null)
            Positioned(
              bottom: collapsed + 12,
              left: 16,
              right: 16,
              child: _buildSelectionCard(height < 450),
            ),
          AnimatedBuilder(
            animation: _expansion,
            builder: (context, _) {
              final progress = _expansion.value;
              final panelHeight = collapsed + travel * progress;
              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: panelHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) => _expansion.stop(),
                  onVerticalDragUpdate: (details) {
                    _expansion.value = (_expansion.value -
                            details.delta.dy / travel)
                        .clamp(0.0, 1.0).toDouble();
                  },
                  onVerticalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    final expand = velocity.abs() > 300
                        ? velocity < 0
                        : _expansion.value >= 0.5;
                    _expansion.animateTo(
                      expand ? 1 : 0,
                      curve: Curves.easeOutCubic,
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        const Color(0xFF11263C),
                        const Color(0xFF081827),
                        progress,
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28.0 * (1.0 - progress)),
                      ),
                      boxShadow: const [BoxShadow(
                        color: Color(0x44000000),
                        blurRadius: 20,
                      )],
                    ),
                    child: AnimatedBuilder(
                      animation: _headingChanges,
                      builder: (context, _) => CompassPanel(
                        progress: progress,
                        destination: widget.controller.destination,
                        distanceMeters: widget.controller.distanceMeters,
                        destinationBearing:
                            widget.controller.destinationBearing,
                        heading: widget.controller.heading.value,
                        filteredHeading:
                            widget.controller.filteredHeading.value,
                        onClear: widget.controller.clearDestination,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ]);
      }),
    ),
  );

  Widget _buildMap(double collapsed) {
    if (!widget.mapConfigured) {
      return _mapNotice(
        '네이버 지도 Client ID가 설정되지 않았습니다.',
        '실행 시 --dart-define=NAVER_MAP_CLIENT_ID=발급받은_ID를 지정하세요.',
      );
    }
    return Stack(children: [
      Positioned.fill(
        child: KeyedSubtree(
          key: ValueKey(_mapGeneration),
          child: widget.mapProvider.buildMap(
            bottomPadding: collapsed + 8,
            onPicked: widget.controller.selectPoint,
            onNamedPlacePicked: (point, name) =>
                widget.controller.selectPoint(point, name: name),
            onLoaded: () {
              _mapTimeout?.cancel();
              if (mounted) {
                setState(() {
                  _mapLoaded = true;
                  _mapTimedOut = false;
                });
              }
            },
            onGesture: () {
              if (mounted && _following) {
                setState(() => _following = false);
              }
            },
          ),
        ),
      ),
      ValueListenableBuilder<String?>(
        valueListenable: widget.mapError,
        builder: (context, authError, _) {
          final message = authError ?? _mapOperationError ??
              (widget.controller.hasNetwork == false
                  ? '온라인 지도를 불러올 수 없습니다.'
                  : _mapTimedOut ? '지도 로딩 시간이 초과되었습니다.' : null);
          if (message != null) {
            return Positioned.fill(child: _mapNotice(message,
                '연결 상태와 네이버 지도 설정을 확인하세요.', onRetry: _retryMap));
          }
          if (_mapLoaded) return const SizedBox.shrink();
          return const Center(child: CircularProgressIndicator.adaptive());
        },
      ),
    ]);
  }

  Widget _mapNotice(String title, String detail, {VoidCallback? onRetry}) =>
      ColoredBox(
        color: const Color(0xFFDEEAF1),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.map_outlined, size: 34, color: Color(0xFF426279)),
                const SizedBox(height: 8),
                Text(title, textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF213F54),
                        fontWeight: FontWeight.w700)),
                Text(detail, textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF426279), fontSize: 12)),
                if (onRetry != null)
                  TextButton(onPressed: onRetry, child: const Text('다시 시도')),
              ]),
            ),
          ),
        ),
      );

  Widget _buildHeader() {
    final controller = widget.controller;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xEE10273C),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(children: [
                const Icon(Icons.navigation_rounded,
                    color: Color(0xFF6BDBED)),
                const SizedBox(width: 8),
                const Expanded(child: Text('목적지 나침반',
                    style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w700))),
                if (controller.destination != null)
                  IconButton(
                    tooltip: '목적지 해제',
                    onPressed: controller.clearDestination,
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                IconButton(
                  tooltip: '내 위치로 이동',
                  onPressed: _recenter,
                  icon: Icon(
                    _following ? Icons.my_location : Icons.location_searching,
                    color: Colors.white,
                  ),
                ),
              ]),
            ),
          ),
          if (controller.locationState != LocationState.ready ||
              controller.persistenceFailed)
            _buildLocationBanner(),
        ]),
      ),
    );
  }

  Widget _buildLocationBanner() {
    final controller = widget.controller;
    final (label, action, callback) = switch (controller.locationState) {
      LocationState.permissionDenied => (
          '위치 권한이 필요합니다.', '권한 요청',
          () => controller.refreshLocation(requestPermission: true)),
      LocationState.permissionDeniedForever => (
          '위치 권한이 거부되었습니다.', '설정 열기',
          controller.openAppSettings),
      LocationState.serviceDisabled => (
          '위치 서비스가 꺼져 있습니다.', '설정 열기',
          controller.openLocationSettings),
      LocationState.poorAccuracy => (
          'GPS 정확도가 낮습니다.', '다시 확인',
          controller.refreshLocation),
      LocationState.unavailable => (
          '현재 위치를 받을 수 없습니다.', '다시 시도',
          () => controller.refreshLocation(requestPermission: true)),
      LocationState.checking || LocationState.acquiring => (
          '현재 위치를 확인하고 있습니다.', '', null),
      LocationState.ready => ('', '', null),
    };
    final message = controller.persistenceFailed
        ? '목적지를 저장하지 못했습니다. 앱을 종료하면 사라질 수 있습니다.'
        : label;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xEE263E50),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(children: [
            const Icon(Icons.info_outline, color: Color(0xFFFFD099), size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text(message,
                style: const TextStyle(color: Colors.white, fontSize: 12))),
            if (callback != null && !controller.persistenceFailed)
              TextButton(onPressed: () => unawaited(callback()),
                  child: Text(action)),
          ]),
        ),
      ),
    );
  }

  Widget _buildSelectionCard(bool compact) {
    final controller = widget.controller;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          elevation: 8,
          child: Padding(
            padding: EdgeInsets.all(compact ? 8 : 14),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('선택한 위치 · ${controller.selectedName ?? controller.selectedPoint!.label}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: controller.cancelSelection,
                  child: const Text('취소'),
                )),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(
                  key: const Key('confirm_destination'),
                  onPressed: controller.confirmSelection,
                  child: const Text('목적지로 설정'),
                )),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
