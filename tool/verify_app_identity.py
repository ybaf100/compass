"""Fail CI if regenerated production platform settings drift from the app ID."""

from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
app_id = 'com.ybaf100.compass'
gradle = root / 'android/app/build.gradle.kts'
if not gradle.exists():
    gradle = root / 'android/app/build.gradle'
contents = gradle.read_text()
for key in ('namespace', 'applicationId'):
    values = re.findall(rf'(?m)^\s*{key}\s*(?:=\s*)?["\']([^"\']+)["\']',
                        contents)
    if values != [app_id]:
        raise SystemExit(f'Invalid Android {key}: {values}')

activity = root / 'android/app/src/main/kotlin/com/ybaf100/compass/MainActivity.kt'
if not activity.exists() or not re.search(r'^package com\.ybaf100\.compass$',
                                            activity.read_text(), re.MULTILINE):
    raise SystemExit('MainActivity path or package does not match app ID')
for other in (root / 'android/app/src/main/kotlin').rglob('MainActivity.kt'):
    if other != activity:
        raise SystemExit(f'Duplicate generated MainActivity: {other}')

project = (root / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
identifiers = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', project)
if len(identifiers) < 3 or app_id not in identifiers:
    raise SystemExit('iOS Runner identifiers missing')
if any(value not in (app_id, app_id + '.RunnerTests') for value in identifiers):
    raise SystemExit(f'Unexpected iOS bundle identifier: {identifiers}')
if any('com.example' in value for value in identifiers):
    raise SystemExit('Placeholder iOS bundle identifier found')
print(f'Platform app identity verified: {app_id}')
