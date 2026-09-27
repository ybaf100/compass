import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/geo_point.dart';
import '../destination/bearing_engine.dart';
import '../navigation/navigation_target.dart';
import '../room/member_model.dart';
import '../room/room_controller.dart';
import 'compass_panel.dart';

class RoomSheet extends StatefulWidget {
  const RoomSheet({super.key, required this.roomController,
    required this.navigation, required this.myPoint,
    required this.onFocusMember});

  final RoomController roomController;
  final NavigationTargetController navigation;
  final GeoPoint? myPoint;
  final void Function(RoomMember) onFocusMember;

  @override
  State<RoomSheet> createState() => _RoomSheetState();
}

class _RoomSheetState extends State<RoomSheet> {
  final _nickname = TextEditingController();
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nickname.text = widget.roomController.nickname ?? '';
  }

  @override
  void dispose() {
    _nickname.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(RoomController.readableError(e))));
      }
    }
  }

  Future<void> _prepareNickname() async {
    final name = _nickname.text.trim();
    if (name != widget.roomController.nickname) {
      await widget.roomController.setNickname(name);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: AnimatedBuilder(
          animation: Listenable.merge([widget.roomController, widget.navigation]),
          builder: (context, _) {
            final controller = widget.roomController;
            final room = controller.room;
            return ListView(shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(child: Container(width: 42, height: 4,
                  decoration: BoxDecoration(color: Colors.blueGrey.shade300,
                    borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 18),
                Text(room == null ? '친구방' : '친구방 · ${controller.members.length}명',
                  style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                if (!controller.configured)
                  const Text('Room을 사용하려면 Supabase 프로젝트 설정이 필요합니다. '
                    '개인 목적지 기능은 계속 사용할 수 있습니다.'),
                if (controller.error != null) ...[
                  Text(controller.error!, style: const TextStyle(color: Colors.red)),
                  TextButton(onPressed: () => unawaited(controller.reconnect()),
                    child: const Text('다시 연결')),
                ],
                TextField(controller: _nickname,
                  maxLength: 24,
                  decoration: const InputDecoration(labelText: '닉네임',
                    hintText: '친구에게 보일 이름')),
                Align(alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => _run(() async {
                    await _prepareNickname();
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('닉네임을 저장했습니다.')));
                    }
                  }), child: const Text('닉네임 저장'))),
                if (room == null) ...[
                  FilledButton(onPressed: !controller.configured || controller.busy
                      ? null : () => _run(() async {
                          await _prepareNickname();
                          await controller.createRoom();
                        }),
                    child: const Text('Room 생성')),
                  const SizedBox(height: 10),
                  TextField(controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    decoration: const InputDecoration(labelText: '초대 코드',
                      hintText: '7KQ3M2')),
                  OutlinedButton(onPressed: !controller.configured || controller.busy
                      ? null : () => _run(() async {
                          await _prepareNickname();
                          final result = await controller.joinRoom(_code.text);
                          if (result.alreadyJoined && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('이미 참가한 방입니다.')));
                          }
                        }),
                    child: const Text('코드로 참가')),
                ] else ...[
                  const Text('위치 공유 중 · 앱이 화면에 있을 때만 위치를 전송합니다.'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: Text('초대 코드: ${room.inviteCode}',
                      style: const TextStyle(fontWeight: FontWeight.bold))),
                    TextButton.icon(
                      onPressed: () => _run(() async {
                        await Clipboard.setData(ClipboardData(text: room.inviteCode));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('초대 코드를 복사했습니다.')));
                        }
                      }),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('복사')),
                  ]),
                  const Divider(),
                  Wrap(spacing: 8, children: [
                    ChoiceChip(label: const Text('내 목적지'),
                      selected: widget.navigation.mode == TargetMode.personal,
                      onSelected: (_) => widget.navigation.selectPersonal()),
                    if (room.sharedDestination != null)
                      ChoiceChip(label: const Text('모두의 목적지'),
                        selected: widget.navigation.mode == TargetMode.shared,
                        onSelected: (_) => widget.navigation.selectShared()),
                  ]),
                  const SizedBox(height: 8),
                  for (final member in controller.members)
                    _memberTile(member, controller),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _run(() async {
                      await controller.leave();
                      if (context.mounted) Navigator.pop(context);
                    }),
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text('방 나가기')),
                ],
              ]);
          },
        ),
      ),
    ),
  ));

  Widget _memberTile(RoomMember member, RoomController controller) {
    final self = member.userId == controller.userId;
    final stale = member.isStale(controller.currentTime, RoomController.staleAfter);
    final myPoint = widget.myPoint;
    final distance = member.point != null && myPoint != null
        ? BearingEngine.distanceMeters(myPoint, member.point!) : null;
    final age = controller.currentTime.difference(member.updatedAt);
    final subtitle = self ? '나' : member.point == null ? '위치 정보 없음'
        : '${CompassPanel.formatDistance(distance)} · '
          '${age.inMinutes > 0 ? '${age.inMinutes}분' : '${age.inSeconds.clamp(0, 59)}초'} 전'
          '${stale ? ' · 오래된 위치' : ''}';
    return ListTile(
      dense: true, contentPadding: EdgeInsets.zero,
      leading: Icon(self ? Icons.my_location : Icons.person_pin_circle,
        color: stale ? Colors.grey : const Color(0xFF15977B)),
      title: Text(member.nickname), subtitle: Text(subtitle),
      onTap: self ? null : () {
        Navigator.pop(context);
        widget.onFocusMember(member);
      },
      trailing: self ? null : const Icon(Icons.chevron_right),
    );
  }
}
