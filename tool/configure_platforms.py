"""Apply the native platform settings after `flutter create`. Idempotent."""

from pathlib import Path
import plistlib
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
app_id = 'com.ybaf100.compass'
app_name = 'passcom'
manifest = root / 'android/app/src/main/AndroidManifest.xml'
android_ns = 'http://schemas.android.com/apk/res/android'
ET.register_namespace('android', android_ns)
tree = ET.parse(manifest)
element = tree.getroot()
application = element.find('application')
if application is None:
    raise RuntimeError('Flutter Android application entry not found')
application.set(f'{{{android_ns}}}label', app_name)
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
    for key in ('namespace', 'applicationId'):
        pattern = rf'(?m)^(\s*{key}\s*(?:=\s*)?)["\'][^"\']+["\']'
        gradle, count = re.subn(pattern, lambda m: f'{m.group(1)}"{app_id}"',
                                 gradle)
        if count != 1:
            raise RuntimeError(f'Android {key} anchor not found in {path}')
    gradle = gradle.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
    gradle = gradle.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 24')
    gradle = gradle.replace('compileSdk = flutter.compileSdkVersion', 'compileSdk = 36')
    gradle = gradle.replace('compileSdkVersion flutter.compileSdkVersion', 'compileSdkVersion 36')
    path.write_text(gradle)

# Keep the native bridge on a tested AGP/Kotlin pair alongside Mapbox.
settings = root / 'android/settings.gradle.kts'
if settings.exists():
    contents = settings.read_text()
    contents, count = re.subn(
        r'id\("com\.android\.application"\) version "[^"]+" apply false',
        'id("com.android.application") version "8.11.1" apply false', contents)
    if count != 1:
        raise RuntimeError('Flutter AGP version anchor not found')
    contents, count = re.subn(
        r'id\("org\.jetbrains\.kotlin\.android"\) version "[^"]+" apply false',
        'id("org.jetbrains.kotlin.android") version "2.2.20" apply false',
        contents)
    if count != 1:
        raise RuntimeError('Flutter Kotlin version anchor not found')
    settings.write_text(contents)

app_gradle = root / 'android/app/build.gradle.kts'
if app_gradle.exists():
    contents = app_gradle.read_text()
    anchor = '    id("com.android.application")\n'
    if '    id("org.jetbrains.kotlin.android")\n' not in contents:
        if anchor not in contents:
            raise RuntimeError('Flutter Android app plugin anchor not found')
        contents = contents.replace(anchor,
            anchor + '    id("org.jetbrains.kotlin.android")\n', 1)
    dependency = 'implementation("com.kakao.maps.open:android:2.15.2")'
    if dependency not in contents:
        contents += '\ndependencies {\n    ' + dependency + '\n}\n'
    app_gradle.write_text(contents)

project_gradle = root / 'android/build.gradle.kts'
if project_gradle.exists():
    contents = project_gradle.read_text()
    repository = 'maven(url = "https://devrepo.kakao.com/nexus/repository/kakaomap-releases/")'
    if repository not in contents:
        anchor = '    repositories {\n'
        if anchor not in contents:
            raise RuntimeError('Android repositories anchor not found')
        contents = contents.replace(anchor, anchor + '        ' + repository + '\n', 1)
    project_gradle.write_text(contents)

wrapper = root / 'android/gradle/wrapper/gradle-wrapper.properties'
if wrapper.exists():
    contents, count = re.subn(r'gradle-[0-9.]+-all\.zip',
                              'gradle-8.14-all.zip', wrapper.read_text())
    if count != 1:
        raise RuntimeError('Gradle wrapper version anchor not found')
    wrapper.write_text(contents)

gradle_properties = root / 'android/gradle.properties'
if gradle_properties.exists():
    properties = gradle_properties.read_text()
    properties = re.sub(r'^android\.builtInKotlin=.*$',
                        'android.builtInKotlin=false', properties,
                        flags=re.MULTILINE)
    if 'android.builtInKotlin=' not in properties:
        properties += '\nandroid.builtInKotlin=false\n'
    gradle_properties.write_text(properties)

info = root / 'ios/Runner/Info.plist'
with info.open('rb') as file:
    data = plistlib.load(file)
data['NSLocationWhenInUseUsageDescription'] = (
    '현재 위치에서 목적지까지의 거리와 방향을 표시하는 데 위치 정보가 필요합니다.')
data['CFBundleDisplayName'] = app_name
data['CFBundleName'] = app_name
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
        pod = re.sub(r'^\s*#?\s*platform :ios,.*$', "platform :ios, '15.0'",
                     pod, count=1, flags=re.MULTILINE)
    else:
        pod = "platform :ios, '15.0'\n" + pod
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
    kakao_pod = "  pod 'KakaoMapsSDK', '2.12.19'\n"
    if kakao_pod not in pod:
        anchor = '  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))'
        if anchor not in pod:
            raise RuntimeError('Flutter Runner pods anchor not found')
        pod = pod.replace(anchor, kakao_pod + anchor, 1)
    podfile.write_text(pod)

# Flutter's Swift-Package-first template no longer includes CocoaPods xcconfigs.
# Kakao's official iOS distribution uses CocoaPods, while Mapbox remains SPM.
for configuration in ('Debug', 'Release'):
    xcconfig = root / f'ios/Flutter/{configuration}.xcconfig'
    if not xcconfig.exists():
        continue
    contents = xcconfig.read_text()
    pods_include = (f'#include? "Pods/Target Support Files/Pods-Runner/'
                    f'Pods-Runner.{configuration.lower()}.xcconfig"')
    if pods_include not in contents:
        xcconfig.write_text(pods_include + '\n' + contents)

project = root / 'ios/Runner.xcodeproj/project.pbxproj'
if project.exists():
    text = project.read_text()
    def bundle_id(match: re.Match[str]) -> str:
        suffix = '.RunnerTests' if match.group(1).endswith('.RunnerTests') else ''
        return f'PRODUCT_BUNDLE_IDENTIFIER = {app_id}{suffix};'

    text, count = re.subn(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', bundle_id, text)
    if count < 3:
        raise RuntimeError('iOS Runner bundle identifier anchors not found')
    text = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;',
                  'IPHONEOS_DEPLOYMENT_TARGET = 15.0;', text)
    project.write_text(text)
