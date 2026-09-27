import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/geo_point.dart';
import '../destination/destination_controller.dart';
import '../destination/bearing_engine.dart';
import '../map/map_provider.dart';
import '../map/member_marker_motion.dart';
import '../navigation/navigation_target.dart';
import '../room/room_controller.dart';
import 'compass_panel.dart';
import 'room_sheet.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.controller,
    required this.mapProvider,
    required this.mapConfigured,
    required this.mapError,
    this.roomController,
    this.navigationController,
  });

  final DestinationController controller;
  final MapProvider mapProvider;
  final bool mapConfigured;
  final ValueListenable<String?> mapError;
  final RoomController? roomController;
  final NavigationTargetController? navigationController;

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
  late final MemberMarkerMotion _memberMotion = MemberMarkerMotion(
    vsync: this,
    onFrame: (members) => _runMap(widget.mapProvider.setMembers(members)),
  );

  Timer? _mapTimeout;
  int _mapGeneration = 0;
  bool _mapLoaded = false;
  bool _mapTimedOut = false;
  bool _following = true;
  GeoPoint? _lastDestinationPoint;
  String? _mapOperationError;
  String? _lastRoomId;
  DateTime? _lastSharedRevision;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerChanged);
    widget.roomController?.addListener(_onRoomChanged);
    widget.navigationController?.addListener(_onControllerChanged);
    if (widget.mapConfigured) _armMapTimeout();
    unawaited(widget.controller.start());
    if (widget.roomController != null) {
      unawaited(widget.roomController!.start());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.onAppResume());
      widget.roomController?.setForeground(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      widget.roomController?.setForeground(false);
    }
  }

  void _onControllerChanged() {
    final target = widget.navigationController?.target;
    final destination = widget.navigationController == null
        ? widget.controller.destination : target?.asDestination;
    final point = destination?.point;
    if (point != null && point != _lastDestinationPoint &&
        target?.mode != TargetMode.member) {
      _pinReveal.forward(from: 0.15);
    }
    _lastDestinationPoint = point;
    _runMap(widget.mapProvider.setDestination(destination));
    _runMap(widget.mapProvider.setCandidate(widget.controller.selectedPoint));
    _runMap(widget.mapProvider.setUserLocation(
      widget.controller.location,
      follow: _following,
    ));
    if (mounted) setState(() {});
  }

  void _onRoomChanged() {
    final state = widget.roomController;
    if (state == null) return;
    final currentRoom = state.room;
    final revision = currentRoom?.sharedDestination?.updatedAt;
    if (currentRoom?.id == _lastRoomId && revision != null &&
        revision != _lastSharedRevision) {
      final authorId = currentRoom!.sharedDestination!.updatedBy;
      final author = state.member(authorId)?.nickname ?? '친구';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$author님이 ${currentRoom.sharedDestination!.title}을(를) '
            '모두의 목적지로 지정했습니다.'),
          duration: const Duration(seconds: 3),
        ));
      });
    }
    _lastRoomId = currentRoom?.id;
    _lastSharedRevision = revision;
    _memberMotion.update([
      for (final member in state.members)
        if (member.userId != state.userId && member.point != null)
          MapMemberOverlay(id: member.userId, name: member.nickname,
            point: member.point!, updatedAt: member.updatedAt,
            isStale: member.isStale(state.currentTime, RoomController.staleAfter)),
    ]);
    _runMap(widget.mapProvider.setSharedPings([
      for (final ping in state.activePings)
        MapPingOverlay(id: ping.id, point: ping.point,
          label: '${ping.createdByNickname} · Ping'),
    ]));
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
    widget.roomController?.removeListener(_onRoomChanged);
    widget.navigationController?.removeListener(_onControllerChanged);
    _memberMotion.dispose();
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
                        destination: widget.navigationController == null
                            ? widget.controller.destination
                            : widget.navigationController!.target?.asDestination,
                        distanceMeters: widget.navigationController == null
                            ? widget.controller.distanceMeters
                            : widget.navigationController!.distanceMeters,
                        destinationBearing: widget.navigationController == null
                            ? widget.controller.destinationBearing
                            : widget.navigationController!.bearing,
                        heading: widget.controller.heading.value,
                        filteredHeading:
                            widget.controller.filteredHeading.value,
                        modeLabel: widget.navigationController?.target?.modeLabel,
                        notice: widget.navigationController?.target?.notice,
                        emptyMessage: widget.navigationController?.target?.notice,
                        clearLabel: widget.navigationController == null ||
                            widget.navigationController!.mode == TargetMode.personal
                            ? '목적지 해제' : '내 목적지로 전환',
                        onClear: widget.navigationController == null ||
                            widget.navigationController!.mode == TargetMode.personal
                            ? widget.controller.clearDestination
                            : widget.navigationController!.selectPersonal,
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
            onMemberTapped: _showMember,
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
                  tooltip: '친구방',
                  onPressed: _showRoomSheet,
                  icon: Icon(Icons.people_alt_outlined,
                    color: widget.roomController?.room == null
                        ? Colors.white : const Color(0xFF69E1F5)),
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
          if (widget.roomController?.room != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(alignment: Alignment.centerLeft,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('친구방 · ${widget.roomController!.members.length}명 · '
                    '${widget.roomController!.sharingLocation ? '위치 공유 중' : '위치 공유 대기'}'),
                )),
            ),
          if (widget.roomController?.error != null)
            Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(widget.roomController!.error!,
                style: const TextStyle(color: Color(0xFFFFD099), fontSize: 12))),
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
                  onPressed: () {
                    controller.confirmSelection();
                    widget.navigationController?.selectPersonal();
                  },
                  child: Text(widget.roomController?.room == null
                      ? '목적지로 설정' : '내 목적지'),
                )),
              ]),
              if (widget.roomController?.room != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => _shareSelection(ping: true),
                    child: const Text('친구들에게 Ping'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.tonal(
                    onPressed: () => _shareSelection(ping: false),
                    child: const Text('모두의 목적지'))),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _shareSelection({required bool ping}) async {
    final point = widget.controller.selectedPoint;
    final room = widget.roomController;
    if (point == null || room?.room == null) return;
    try {
      if (ping) {
        await room!.sendPing(point);
      } else {
        await room!.setSharedDestination(point, widget.controller.selectedName);
      }
      widget.controller.cancelSelection();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RoomController.readableError(e))));
      }
    }
  }

  void _showRoomSheet() {
    final room = widget.roomController;
    final navigation = widget.navigationController;
    if (room == null || navigation == null) return;
    showModalBottomSheet<void>(context: context, isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => RoomSheet(roomController: room,
        navigation: navigation, myPoint: widget.controller.location?.point,
        onFocusMember: (member) => _showMember(member.userId)));
  }

  void _showMember(String id) {
    final room = widget.roomController;
    final member = room?.member(id);
    if (room == null || member == null) return;
    final own = widget.controller.location?.point;
    final meters = own != null && member.point != null
        ? BearingEngine.distanceMeters(own, member.point!) : null;
    showModalBottomSheet<void>(context: context, showDragHandle: true,
      builder: (context) => SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(member.nickname, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(member.point == null ? '위치 정보 없음'
                : '${CompassPanel.formatDistance(meters)} · '
                  '마지막 업데이트 ${room.currentTime.difference(member.updatedAt).inSeconds}초 전'),
            if (member.isStale(room.currentTime, RoomController.staleAfter))
              const Text('위치가 오래되었습니다.',
                style: TextStyle(color: Colors.orange)),
            const SizedBox(height: 14),
            FilledButton(onPressed: member.point == null ? null : () {
              widget.navigationController?.followMember(id);
              Navigator.pop(context);
            }, child: const Text('친구 따라가기')),
          ])),
      ))));
  }
}
