import 'package:flutter/material.dart';

import '../core/config/service_configuration.dart';
import '../core/config/service_initialization.dart';
import '../core/network/network_monitor.dart';
import '../core/location/location_provider.dart';
import '../map/kakao_map_state.dart';

/// Never accepts or renders raw IDs, keys, tokens, or URLs.
class ServiceStatusSheet extends StatelessWidget {
  const ServiceStatusSheet({super.key, required this.kakao,
    required this.supabase, required this.mapbox,
    this.network = const NetworkStatus.unknown(),
    this.kakaoState = KakaoState.initializing, this.kakaoFailure,
    this.supabaseInitialization = const ServiceInitialization.initialized(),
    this.mapboxInitialization = const ServiceInitialization.initialized(),
    this.mapboxFailed = false, this.locationAccess,
    this.locationPrecision = LocationPrecision.unknown, this.locationFailure,
    this.waitingForLocation = false});

  final ConfigurationStatus kakao;
  final ConfigurationStatus supabase;
  final ConfigurationStatus mapbox;
  final NetworkStatus network;
  final KakaoState kakaoState;
  final KakaoFailure? kakaoFailure;
  final ServiceInitialization supabaseInitialization;
  final ServiceInitialization mapboxInitialization;
  final bool mapboxFailed;
  final LocationAccess? locationAccess;
  final LocationPrecision locationPrecision;
  final LocationFailure? locationFailure;
  final bool waitingForLocation;

  @override
  Widget build(BuildContext context) => SafeArea(child: Center(
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24),
        children: [
          Text('서비스 상태', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('연결 인터페이스는 인터넷 접속을 보장하지 않습니다. SDK 초기화와 실제 지도·친구방·다운로드 연결은 별도로 확인하세요.'),
          const SizedBox(height: 16),
          ListTile(title: const Text('Network'), subtitle: Text(
            network.failure != null ? '상태 확인 실패 · ${network.failure!.name}'
                : switch (network.state) {
                    NetworkState.unknown => '확인 중',
                    NetworkState.available => '연결 인터페이스 있음',
                    NetworkState.unavailable => '연결 없음',
                  })),
          _entry('Kakao Maps', kakao,
            issue: switch (kakaoState) {
              KakaoState.notConfigured => '설정 안 됨',
              KakaoState.initializing => '초기화 중 · 지도 연결 확인 필요',
              KakaoState.loaded => '지도 로드 성공',
              KakaoState.failed => '인증/초기화 실패 · ${kakaoFailure?.name ?? 'initialization'}',
              KakaoState.timedOut => 'timeout · 카카오 지도 응답 없음',
            }),
          _entry('Supabase', supabase,
            issue: _initializationLabel(supabaseInitialization)),
          _entry('Mapbox', mapbox,
            issue: mapboxFailed ? '실행 실패 · 지도/다운로드 확인 필요'
                : _initializationLabel(mapboxInitialization)),
          ListTile(title: const Text('Location'), subtitle: Text(
            locationFailure != null ? '위치 오류 · ${locationFailure!.name}'
                : waitingForLocation ? '현재 위치를 찾는 중입니다.'
                : locationAccess?.name ?? '권한 확인 중')),
          ListTile(title: const Text('위치 정확도 권한'),
            subtitle: Text(locationPrecision.name)),
          const Divider(height: 30),
          const ListTile(title: Text('Android package'),
            subtitle: Text(ServiceConfiguration.appIdentifier)),
          const ListTile(title: Text('iOS / iPadOS Bundle ID'),
            subtitle: Text(ServiceConfiguration.appIdentifier)),
        ]),
    ),
  ));

  static String _initializationLabel(ServiceInitialization result) => switch (result.state) {
    InitializationState.notConfigured => '설정 안 됨',
    InitializationState.initializing => '초기화 중',
    InitializationState.initialized => '초기화 완료 · 서비스 연결은 별도 확인',
    InitializationState.failed => '초기화 실패 · ${result.failure?.name ?? 'unexpected'}',
  };

  Widget _entry(String name, ConfigurationStatus status, {String? issue}) {
    final label = switch (status) {
      ConfigurationStatus.missing => '미입력',
      ConfigurationStatus.invalid => '형식 오류',
      ConfigurationStatus.configured => issue ?? '설정됨 · 연결 미확인',
    };
    return ListTile(title: Text(name), subtitle: Text(label),
      leading: Icon(status == ConfigurationStatus.configured && issue == null
        ? Icons.check_circle_outline : Icons.info_outline));
  }
}
