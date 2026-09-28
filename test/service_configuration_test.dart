import 'package:destination_compass/core/config/service_configuration.dart';
import 'package:destination_compass/ui/service_status_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const empty = ServiceConfiguration(naverClientId: '', supabaseUrl: '',
    supabasePublishableKey: '', mapboxAccessToken: '');
  const valid = ServiceConfiguration(naverClientId: 'naver-id',
    supabaseUrl: 'https://example.supabase.co',
    supabasePublishableKey: 'sb_publishable_test',
    mapboxAccessToken: 'pk.test');

  test('missing credentials disable only the corresponding services', () {
    expect(empty.naverStatus, ConfigurationStatus.missing);
    expect(empty.supabaseStatus, ConfigurationStatus.missing);
    expect(empty.mapboxStatus, ConfigurationStatus.missing);
    expect(empty.naverConfigured, isFalse);
    expect(empty.supabaseConfigured, isFalse);
    expect(empty.mapboxConfigured, isFalse);
    expect(valid.naverConfigured, isTrue);
    expect(valid.supabaseConfigured, isTrue);
    expect(valid.mapboxConfigured, isTrue);
  });

  test('rejects invalid or privileged client configuration', () {
    const config = ServiceConfiguration(naverClientId: 'bad id',
      supabaseUrl: 'http://example.supabase.co',
      supabasePublishableKey: 'sb_secret_test',
      mapboxAccessToken: 'sk.test');
    expect(config.naverStatus, ConfigurationStatus.invalid);
    expect(config.supabaseStatus, ConfigurationStatus.invalid);
    expect(config.mapboxStatus, ConfigurationStatus.invalid);
    const partial = ServiceConfiguration(naverClientId: '',
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: '', mapboxAccessToken: '');
    expect(partial.supabaseStatus, ConfigurationStatus.invalid);
  });

  testWidgets('diagnostics describe configuration without showing values',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:
      ServiceStatusSheet(naver: ConfigurationStatus.configured,
        supabase: ConfigurationStatus.missing,
        mapbox: ConfigurationStatus.invalid))));
    expect(find.text('설정됨 · 연결 미확인'), findsOneWidget);
    expect(find.text('미입력'), findsOneWidget);
    expect(find.text('형식 오류'), findsOneWidget);
    expect(find.text(ServiceConfiguration.appIdentifier), findsNWidgets(2));
    expect(find.textContaining('pk.test'), findsNothing);
    expect(find.textContaining('sb_publishable_test'), findsNothing);
  });
}
