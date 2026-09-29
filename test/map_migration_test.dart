import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production configuration contains no legacy online map references', () {
    final forbidden = [
      'flutter_' + 'naver_map',
      'NAVER_' + 'MAP_CLIENT_ID',
      'Naver' + 'MapProvider',
    ];
    final files = <File>[
      ...Directory('lib').listSync(recursive: true).whereType<File>(),
      ...Directory('platform_overrides').listSync(recursive: true).whereType<File>(),
      File('pubspec.yaml'), File('config/defines.example.json'),
      File('.github/workflows/verify.yml'), File('README.md'), File('SETUP.md'),
    ];
    for (final file in files) {
      final content = file.readAsStringSync();
      for (final reference in forbidden) {
        expect(content.contains(reference), isFalse,
          reason: '${file.path} still references a removed map dependency');
      }
    }
  });
}
