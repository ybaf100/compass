import 'package:flutter/material.dart';

import '../core/config/service_configuration.dart';
import '../core/config/service_initialization.dart';
import '../core/network/network_monitor.dart';
import '../core/location/location_provider.dart';
import '../map/kakao_map_state.dart';
import '../map/kakao_diagnostics.dart';

/// Only the requested public Bundle ID and whitelisted SDK states are shown.
/// Never accepts or renders keys, tokens, coordinates or raw SDK descriptions.
class ServiceStatusSheet extends StatelessWidget {
  const ServiceStatusSheet({super.key, required this.kakao,
    required this.supabase, required this.mapbox,
    this.network = const NetworkStatus.unknown(),
    this.kakaoState = KakaoState.initializing, this.kakaoFailure,
    this.supabaseInitialization = const ServiceInitialization.initialized(),
    this.mapboxInitialization = const ServiceInitialization.initialized(),
    this.mapboxFailed = false, this.locationAccess,
    this.locationPrecision = LocationPrecision.unknown, this.locationFailure,
    this.waitingForLocation = false,
    this.kakaoDiagnostics = const KakaoDiagnostics()});

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
  final KakaoDiagnostics kakaoDiagnostics;

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
              KakaoState.timedOut => kakaoFailure == KakaoFailure.prepareTimeout
                  ? 'prepare timeout · 카카오 지도 준비 응답 없음'
                  : 'timeout · 카카오 지도 응답 없음',
            }),
          ListTile(title: const Text('Kakao Native app key'),
            subtitle: Text(kakaoDiagnostics.keyPresent ? 'key present' : 'key missing')),
          ListTile(title: const Text('Kakao SDK'),
            subtitle: Text(kakaoDiagnostics.sdkInitialized
                ? 'SDK initialized' : 'SDK not initialized')),
          ListTile(title: const Text('prepareEngine return'),
            subtitle: Text(kakaoDiagnostics.prepareReturn?.toString() ?? '아직 호출되지 않음')),
          ListTile(title: const Text('Engine prepared'),
            subtitle: Text(_yesNo(kakaoDiagnostics.enginePrepared))),
          ListTile(title: const Text('Engine active'),
            subtitle: Text(_yesNo(kakaoDiagnostics.engineActive))),
          ListTile(title: const Text('Auth callback status'),
            subtitle: Text(kakaoDiagnostics.authCallback.name)),
          ListTile(title: const Text('Engine state summary'),
            subtitle: Text(kakaoDiagnostics.engineStateSummary?.name ?? '확인 중')),
          ListTile(title: const Text('SDK state description'),
            subtitle: Text(kakaoDiagnostics.stateDescriptionAvailable == null
                ? 'debug 빌드에서 확인 · 원문 비공개'
                : '${_yesNo(kakaoDiagnostics.stateDescriptionAvailable)} · 원문 비공개')),
          ListTile(title: const Text('Kakao lifecycle · 마지막 stage'),
            subtitle: Text(kakaoDiagnostics.stage?.name ?? '아직 생성되지 않음')),
          ListTile(title: const Text('Kakao 인증 오류'),
            subtitle: Text(kakaoDiagnostics.authErrorLabel)),
          ListTile(title: const Text('인증/엔진 자동 재시도'),
            subtitle: Text('${kakaoDiagnostics.retryCount}/2 · '
              '${kakaoDiagnostics.retryPending ? '대기 중' : '대기 없음'}')),
          ListTile(title: const Text('Kakao container size'),
            subtitle: Text(kakaoDiagnostics.width == null ? '확인 중'
              : '${kakaoDiagnostics.width!.round()} × ${kakaoDiagnostics.height?.round() ?? 0}')),
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
          const ListTile(title: Text('Expected Bundle ID'),
            subtitle: Text(ServiceConfiguration.appIdentifier)),
          ListTile(title: const Text('Runtime Bundle ID'),
            subtitle: Text(kakaoDiagnostics.runtimeBundleId ?? '확인 불가 / iOS에서 확인')),
          ListTile(title: const Text('Match'), subtitle: Text(
            switch (kakaoDiagnostics.matchesBundleId(ServiceConfiguration.appIdentifier)) {
              true => 'yes', false => 'no', null => '확인 불가',
            })),
        ]),
    ),
  ));

  static String _initializationLabel(ServiceInitialization result) => switch (result.state) {
    InitializationState.notConfigured => '설정 안 됨',
    InitializationState.initializing => '초기화 중',
    InitializationState.initialized => '초기화 완료 · 서비스 연결은 별도 확인',
    InitializationState.failed => '초기화 실패 · ${result.failure?.name ?? 'unexpected'}',
  };

  static String _yesNo(bool? value) => value == null ? '확인 중' : value ? 'yes' : 'no';

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
