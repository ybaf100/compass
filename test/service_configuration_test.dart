import 'dart:async';
import 'dart:io';

import 'package:destination_compass/core/config/service_configuration.dart';
import 'package:destination_compass/core/config/service_initialization.dart';
import 'package:destination_compass/core/network/network_monitor.dart';
import 'package:destination_compass/map/kakao_map_state.dart';
import 'package:destination_compass/ui/service_status_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const empty = ServiceConfiguration(kakaoNativeAppKey: '', supabaseUrl: '',
    supabasePublishableKey: '', mapboxAccessToken: '');
  const valid = ServiceConfiguration(kakaoNativeAppKey: 'kakao-key',
    supabaseUrl: 'https://example.supabase.co',
    supabasePublishableKey: 'sb_publishable_test',
    mapboxAccessToken: 'pk.test');

  test('missing credentials disable only the corresponding services', () {
    expect(empty.kakaoStatus, ConfigurationStatus.missing);
    expect(empty.supabaseStatus, ConfigurationStatus.missing);
    expect(empty.mapboxStatus, ConfigurationStatus.missing);
    expect(empty.kakaoConfigured, isFalse);
    expect(empty.supabaseConfigured, isFalse);
    expect(empty.mapboxConfigured, isFalse);
    expect(valid.kakaoConfigured, isTrue);
    expect(valid.supabaseConfigured, isTrue);
    expect(valid.mapboxConfigured, isTrue);
  });

  test('rejects invalid or privileged client configuration', () {
    const config = ServiceConfiguration(kakaoNativeAppKey: 'bad id',
      supabaseUrl: 'http://example.supabase.co',
      supabasePublishableKey: 'sb_secret_test',
      mapboxAccessToken: 'sk.test');
    expect(config.kakaoStatus, ConfigurationStatus.invalid);
    expect(config.supabaseStatus, ConfigurationStatus.invalid);
    expect(config.mapboxStatus, ConfigurationStatus.invalid);
    const partial = ServiceConfiguration(kakaoNativeAppKey: '',
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: '', mapboxAccessToken: '');
    expect(partial.supabaseStatus, ConfigurationStatus.invalid);
  });

  testWidgets('diagnostics describe configuration without showing values',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      ServiceStatusSheet(kakao: ConfigurationStatus.configured,
        supabase: ConfigurationStatus.missing,
        mapbox: ConfigurationStatus.invalid))));
    expect(find.text('초기화 중 · 지도 연결 확인 필요'), findsOneWidget);
    expect(find.text('미입력'), findsOneWidget);
    expect(find.text('형식 오류'), findsOneWidget);
    expect(find.text(ServiceConfiguration.appIdentifier), findsNWidgets(2));
    expect(find.textContaining('pk.test'), findsNothing);
    expect(find.textContaining('sb_publishable_test'), findsNothing);
  });

  test('service initialization classifies failures without connectivity gating', () async {
    var attempts = 0;
    final success = await initializeService(configured: true, service: 'supabase',
      initialize: () async { attempts++; });
    expect(success.state, InitializationState.initialized);
    expect(attempts, 1);
    final disabled = await initializeService(configured: false, service: 'supabase',
      initialize: () async { attempts++; });
    expect(disabled.state, InitializationState.notConfigured);
    expect(attempts, 1);
    for (final entry in <Object, InitializationFailure>{
      MissingPluginException('do-not-expose-token'): InitializationFailure.plugin,
      const SocketException('do-not-expose-url'): InitializationFailure.network,
      TimeoutException('do-not-expose-url'): InitializationFailure.timeout,
      const FormatException('do-not-expose-key'): InitializationFailure.configuration,
      const FileSystemException('do-not-expose-path'): InitializationFailure.storage,
      StateError('do-not-expose-token'): InitializationFailure.unexpected,
    }.entries) {
      final failed = await initializeService(configured: true, service: 'supabase',
        initialize: () async => throw entry.key);
      expect(failed.state, InitializationState.failed);
      expect(failed.failure, entry.value);
    }
  });

  testWidgets('network unknown failure and SDK timeout are independently diagnosed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      ServiceStatusSheet(kakao: ConfigurationStatus.configured,
        supabase: ConfigurationStatus.configured, mapbox: ConfigurationStatus.configured,
        network: NetworkStatus.unknown(failure: NetworkFailure.plugin),
        kakaoState: KakaoState.timedOut,
        supabaseInitialization: ServiceInitialization(InitializationState.failed,
          failure: InitializationFailure.plugin)))));
    expect(find.text('상태 확인 실패 · plugin'), findsOneWidget);
    expect(find.text('timeout · 카카오 지도 응답 없음'), findsOneWidget);
    expect(find.text('초기화 실패 · plugin'), findsOneWidget);
    expect(find.text('연결 없음'), findsNothing);
    expect(find.textContaining('do-not-expose'), findsNothing);
  });
}
