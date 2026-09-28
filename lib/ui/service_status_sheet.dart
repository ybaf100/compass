import 'package:flutter/material.dart';

import '../core/config/service_configuration.dart';

/// Never accepts or renders raw IDs, keys, tokens, or URLs.
class ServiceStatusSheet extends StatelessWidget {
  const ServiceStatusSheet({super.key, required this.naver,
    required this.supabase, required this.mapbox,
    this.naverError, this.supabaseInitialized = true,
    this.mapboxInitialized = true});

  final ConfigurationStatus naver;
  final ConfigurationStatus supabase;
  final ConfigurationStatus mapbox;
  final String? naverError;
  final bool supabaseInitialized;
  final bool mapboxInitialized;

  @override
  Widget build(BuildContext context) => SafeArea(child: Center(
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24),
        children: [
          Text('서비스 상태', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('입력 형식만 확인합니다. 실제 인증과 연결은 지도·친구방·다운로드를 실행해 확인하세요.'),
          const SizedBox(height: 16),
          _entry('Naver Maps', naver,
            issue: naverError == null ? null : '지도 초기화 또는 인증 실패'),
          _entry('Supabase', supabase,
            issue: supabaseInitialized ? null : '초기화 실패'),
          _entry('Mapbox', mapbox,
            issue: mapboxInitialized ? null : '초기화 실패'),
          const Divider(height: 30),
          const ListTile(title: Text('Android package'),
            subtitle: Text(ServiceConfiguration.appIdentifier)),
          const ListTile(title: Text('iOS / iPadOS Bundle ID'),
            subtitle: Text(ServiceConfiguration.appIdentifier)),
        ]),
    ),
  ));

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
