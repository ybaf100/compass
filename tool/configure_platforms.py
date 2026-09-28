"""Apply the native platform settings after `flutter create`. Idempotent."""

from pathlib import Path
import plistlib
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
manifest = root / 'android/app/src/main/AndroidManifest.xml'
android_ns = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', android_ns)
tree = ET.parse(manifest)
element = tree.getroot()
application = element.find('application')
if application is None:
    raise RuntimeError('Flutter Android application entry not found')
application.set(f'{{{android_ns}}}label', '목적지 나침반')
for permission in ('ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION',
                   'INTERNET', 'ACCESS_NETWORK_STATE'):
    name = f'android.permission.{permission}'
    if not any(e.get(f'{{{android_ns}}}name') == name
               for e in element.findall('uses-permission')):
        node = ET.Element('uses-permission')
        node.set(f'{{{android_ns}}}name', name)
        element.insert(0, node)
tree.write(manifest, encoding='utf-8', xml_declaration=True)

for path in (root / 'android/app/build.gradle.kts',
             root / 'android/app/build.gradle'):
    if not path.exists():
        continue
    gradle = path.read_text()
    gradle = gradle.replace('minSdk = flutter.minSdkVersion', 'minSdk = 23')
    gradle = gradle.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 23')
    gradle = gradle.replace('compileSdk = flutter.compileSdkVersion', 'compileSdk = 36')
    gradle = gradle.replace('compileSdkVersion flutter.compileSdkVersion', 'compileSdkVersion 36')
    path.write_text(gradle)

info = root / 'ios/Runner/Info.plist'
with info.open('rb') as file:
    data = plistlib.load(file)
data['NSLocationWhenInUseUsageDescription'] = (
    '현재 위치에서 목적지까지의 거리와 방향을 표시하는 데 위치 정보가 필요합니다.')
data['CFBundleDisplayName'] = '목적지 나침반'
data['UISupportedInterfaceOrientations'] = [
    'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft',
    'UIInterfaceOrientationLandscapeRight']
data['UISupportedInterfaceOrientations~ipad'] = [
    'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
    'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']
with info.open('wb') as file:
    plistlib.dump(data, file, sort_keys=False)

podfile = root / 'ios/Podfile'
if podfile.exists():
    pod = podfile.read_text()
    if re.search(r'^\s*#?\s*platform :ios,', pod, re.MULTILINE):
        pod = re.sub(r'^\s*#?\s*platform :ios,.*$', "platform :ios, '14.0'",
                     pod, count=1, flags=re.MULTILINE)
    else:
        pod = "platform :ios, '14.0'\n" + pod
    flag = "BYPASS_PERMISSION_LOCATION_ALWAYS=1"
    if flag not in pod:
        anchor = 'flutter_additional_ios_build_settings(target)'
        if anchor not in pod:
            raise RuntimeError('Flutter Podfile post_install anchor not found')
        pod = pod.replace(anchor, anchor + "\n    if target.name == 'geolocator_apple'\n"
            "      target.build_configurations.each do |config|\n"
            "        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']\n"
            f"        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] << '{flag}'\n"
            "      end\n    end")
    podfile.write_text(pod)

project = root / 'ios/Runner.xcodeproj/project.pbxproj'
if project.exists():
    text = project.read_text()
    text = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;',
                  'IPHONEOS_DEPLOYMENT_TARGET = 14.0;', text)
    project.write_text(text)
