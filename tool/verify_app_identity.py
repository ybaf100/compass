"""Verify permanent app identity and branding in sources or compiled artifacts."""

import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APP_ID = 'com.ybaf100.compass'
APP_NAME = 'passcom'


def require_equal(label, actual, expected):
    if actual != expected:
        raise SystemExit(f'Invalid {label}: {actual!r}; expected {expected!r}')


def verify_plist(data, compiled):
    for key in ('CFBundleDisplayName', 'CFBundleName'):
        require_equal(key, data.get(key), APP_NAME)
    expected_id = APP_ID if compiled else '$(PRODUCT_BUNDLE_IDENTIFIER)'
    require_equal('CFBundleIdentifier', data.get('CFBundleIdentifier'), expected_id)


def verify_sources():
    gradle = ROOT / 'android/app/build.gradle.kts'
    if not gradle.exists():
        gradle = ROOT / 'android/app/build.gradle'
    contents = gradle.read_text()
    for key in ('namespace', 'applicationId'):
        values = re.findall(rf'(?m)^\s*{key}\s*(?:=\s*)?["\']([^"\']+)["\']',
                            contents)
        require_equal(f'Android {key}', values, [APP_ID])

    manifest = ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml')
    application = manifest.getroot().find('application')
    if application is None:
        raise SystemExit('Android application entry missing')
    require_equal('Android application label',
                  application.get('{http://schemas.android.com/apk/res/android}label'),
                  APP_NAME)

    activity = ROOT / 'android/app/src/main/kotlin/com/ybaf100/compass/MainActivity.kt'
    if not activity.exists() or not re.search(r'^package com\.ybaf100\.compass$',
                                                activity.read_text(), re.MULTILINE):
        raise SystemExit('MainActivity path or package does not match app ID')
    for other in (ROOT / 'android/app/src/main/kotlin').rglob('MainActivity.kt'):
        if other != activity:
            raise SystemExit(f'Duplicate generated MainActivity: {other}')

    project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
    identifiers = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', project)
    if len(identifiers) < 3 or APP_ID not in identifiers:
        raise SystemExit('iOS Runner identifiers missing')
    if any(value not in (APP_ID, APP_ID + '.RunnerTests') for value in identifiers):
        raise SystemExit(f'Unexpected iOS bundle identifier: {identifiers}')
    verify_plist(plistlib.loads((ROOT / 'ios/Runner/Info.plist').read_bytes()),
                 compiled=False)


def find_aapt():
    executable = shutil.which('aapt')
    if executable:
        return executable
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    if sdk:
        candidates = list((Path(sdk) / 'build-tools').glob('*/aapt'))
        if candidates:
            return str(max(candidates, key=lambda p: tuple(
                int(part) for part in re.findall(r'\d+', p.parent.name))))
    raise SystemExit('aapt not found; set ANDROID_HOME or add build-tools to PATH')


def verify_apk(path):
    badging = subprocess.run([find_aapt(), 'dump', 'badging', str(path)],
                             check=True, capture_output=True, text=True).stdout
    package = re.search(r"^package: name='([^']+)'", badging, re.MULTILINE)
    label = re.search(r"^application-label:'([^']+)'", badging, re.MULTILINE)
    require_equal('APK package', package.group(1) if package else None, APP_ID)
    require_equal('APK application label', label.group(1) if label else None, APP_NAME)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path, help='Verify compiled Android APK with aapt')
    parser.add_argument('--ios-app', type=Path, help='Verify compiled iOS Runner.app')
    parser.add_argument('--ipa', type=Path, help='Verify packaged iOS device IPA')
    args = parser.parse_args()
    if not any((args.apk, args.ios_app, args.ipa)):
        verify_sources()
    if args.apk:
        verify_apk(args.apk)
    if args.ios_app:
        verify_plist(plistlib.loads((args.ios_app / 'Info.plist').read_bytes()),
                     compiled=True)
    if args.ipa:
        with zipfile.ZipFile(args.ipa) as archive:
            data = plistlib.loads(archive.read('Payload/Runner.app/Info.plist'))
        verify_plist(data, compiled=True)
        require_equal('IPA supported platform', data.get('CFBundleSupportedPlatforms'),
                      ['iPhoneOS'])
    print(f'App identity and branding verified: {APP_NAME} ({APP_ID})')


if __name__ == '__main__':
    main()
