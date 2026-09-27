#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
if ! command -v flutter >/dev/null 2>&1; then
  echo 'Flutter SDK가 필요합니다: https://docs.flutter.dev/get-started/install' >&2
  exit 1
fi

flutter create --platforms=android,ios --org com.example \
  --project-name destination_compass --no-pub .
mkdir -p android/app/src/main/kotlin/com/example/destination_compass
cp platform_overrides/android/MainActivity.kt \
  android/app/src/main/kotlin/com/example/destination_compass/MainActivity.kt
cp platform_overrides/ios/AppDelegate.swift ios/Runner/AppDelegate.swift
python3 tool/configure_platforms.py
flutter pub get
echo '플랫폼 설정 완료. README의 Client ID 안내를 확인하세요.'
