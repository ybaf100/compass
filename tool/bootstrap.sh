#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
if ! command -v flutter >/dev/null 2>&1; then
  echo 'Flutter SDK가 필요합니다: https://docs.flutter.dev/get-started/install' >&2
  exit 1
fi

flutter create --platforms=android,ios --org com.ybaf100 \
  --project-name destination_compass --no-pub .
mkdir -p android/app/src/main/kotlin/com/ybaf100/compass
cp platform_overrides/android/MainActivity.kt \
  android/app/src/main/kotlin/com/ybaf100/compass/MainActivity.kt
cp platform_overrides/android/KakaoMapPlatformView.kt \
  android/app/src/main/kotlin/com/ybaf100/compass/KakaoMapPlatformView.kt
mkdir -p android/app/src/test/kotlin/com/ybaf100/compass
cp platform_overrides/android/KakaoMarkerGeometryTest.kt \
  android/app/src/test/kotlin/com/ybaf100/compass/KakaoMarkerGeometryTest.kt
# Flutter's generated class uses the project name; only the permanent package
# path may contain an Activity after regeneration (including older checkouts).
rm -f android/app/src/main/kotlin/com/ybaf100/destination_compass/MainActivity.kt
rm -f android/app/src/main/kotlin/com/example/destination_compass/MainActivity.kt
cp platform_overrides/ios/AppDelegate.swift ios/Runner/AppDelegate.swift
cp platform_overrides/ios/Podfile ios/Podfile
python3 tool/configure_platforms.py
python3 tool/verify_app_identity.py
flutter pub get
echo '플랫폼 설정 완료. SETUP.md의 Kakao Native app key 안내를 확인하세요.'
