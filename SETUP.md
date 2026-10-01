# passcom — 서비스 설정 및 실기기 빌드

## 1. 앱 식별자

서비스명과 Android/iOS/iPadOS 홈 화면 표시 이름은 모두 **passcom**입니다. Flutter MaterialApp 제목과 iOS CFBundleName, 미서명 sideload IPA의 표시 이름도 `passcom`입니다.

Android `applicationId`와 `namespace`, iOS/iPadOS Runner Bundle ID는 모두 `com.ybaf100.compass`입니다. **앱 이름 `passcom`은 플랫폼 인증 식별자가 아닙니다.** Kakao Developers에 등록할 package/Bundle ID는 그대로 유지합니다. 내부 Flutter 프로젝트명은 `destination_compass`, iOS RunnerTests는 `com.ybaf100.compass.RunnerTests`입니다. `bash tool/bootstrap.sh`를 반복해도 표시 이름과 식별자는 유지됩니다. SideStore/AltStore 등 재서명 도구가 Bundle ID를 변경할 수 있으므로 설치 후 실제 ID를 확인하세요.

## 2. Kakao Maps 설정

1. [Kakao Developers](https://developers.kakao.com/)에 로그인해 **앱 관리 → 앱 생성**에서 앱 이름을 **passcom**으로 입력해 앱을 만듭니다. 이미 만든 앱은 이름을 passcom으로 변경하고 기존 플랫폼 식별자를 유지하세요.
2. 해당 앱의 **카카오맵 → 사용 설정**에서 상태를 **ON**으로 설정합니다. 2026년 7월 이후의 지도 API 사용량/무료 할당량 정책과 필요한 결제 설정도 확인합니다.
3. 앱 관리 페이지의 **앱 → 플랫폼 키 → 네이티브 앱 키**에서 값을 복사합니다. **REST API 키, JavaScript 키, Admin 키가 아닙니다.** 이 값을 `KAKAO_NATIVE_APP_KEY`에 입력합니다.
4. 같은 네이티브 앱 키 설정의 **패키지명**에 `com.ybaf100.compass`, **키 해시**에 실제 서명 인증서의 Key Hash를 등록하고 저장합니다. 각 개발자의 debug 키, 릴리스 키, Google Play App Signing 키는 서로 다를 수 있으므로 실제로 배포하는 모든 서명 키의 해시를 등록합니다.
5. 같은 설정의 **번들 ID**에 `com.ybaf100.compass`를 등록하고 저장합니다. iPadOS도 같은 Bundle ID입니다. SideStore/AltStore의 재서명 과정에서 Bundle ID가 변경되면 등록값과 일치하지 않아 인증이 실패할 수 있습니다.

공식 [지도 시작하기](https://developers.kakao.com/docs/ko/kakaomap/common), [네이티브 앱 키 및 플랫폼 정보](https://developers.kakao.com/docs/ko/app-setting/app), [Android 키 해시](https://developers.kakao.com/docs/ko/android/getting-started)를 참고하세요. SDK 자체는 공식 Android v2 `2.15.2`, iOS v2 `2.12.19`를 사용합니다.

### Android 서명 Key Hash

아래 도구는 **실제 APK 서명 인증서**의 SHA-1을 Kakao의 Base64 Key Hash 형식으로 출력합니다. Android SDK의 `apksigner`가 PATH에 있어야 합니다.

```bash
python3 tool/print_android_kakao_key_hash.py --apk build/app/outputs/flutter-apk/app-debug.apk
```

릴리스 keystore가 있다면 `keytool`로 공개 인증서만 추출하여 같은 해시를 계산합니다. 암호는 프롬프트에서 입력하며 저장소나 명령줄에 적지 않습니다.

```bash
python3 tool/print_android_kakao_key_hash.py --keystore /안전한/경로/release.jks --alias 릴리스_별칭
```

GitHub Actions의 현재 `flutter build apk --debug`는 runner가 생성한 **일회성 debug keystore**로 서명될 수 있습니다. 매 실행 인증서가 안정적이라고 가정하지 마세요. CI artifact ZIP에서 APK를 꺼내 첫 번째 명령으로 **그 APK 자체**의 해시를 확인해 등록해야 Kakao 인증을 검증할 수 있습니다. 안정적인 배포용 서명이 필요하면 본인이 관리하는 keystore를 GitHub **Settings → Secrets and variables → Actions → Secrets**에 `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`로 보관하고 별도 release-signing 빌드 단계를 구성하세요. 현재 workflow는 이 Secrets를 사용하지 않으며 keystore를 생성·커밋하지 않습니다.

## 3. Supabase 설정

1. [Supabase Dashboard](https://supabase.com/dashboard)에서 **New project**를 만들고 데이터베이스 준비가 끝날 때까지 기다립니다.
2. 프로젝트 상단 **Connect** 또는 **Project Settings → API Keys**의 *Publishable and secret API keys*에서 Project URL과 `sb_publishable_...` **Publishable key**를 확인합니다. URL을 `SUPABASE_URL`, publishable key를 `SUPABASE_PUBLISHABLE_KEY`에 넣습니다.
3. **Authentication → Settings / General**의 **Allow anonymous sign-ins**를 켭니다. UI 버전에 따라 **Authentication → Sign In / Providers → Anonymous**에서 같은 설정을 찾을 수 있습니다. 앱은 `signInAnonymously()`를 호출합니다.
4. 프로젝트 **SQL Editor → New query**에서 `supabase/migrations/202609270001_rooms.sql` 파일 전체를 붙여넣고 **Run**을 누릅니다. 마이그레이션은 `rooms`, `room_members`, `shared_pings`, RLS, 방/멤버 위치/Ping/공유 목적지 RPC, Realtime publication을 만듭니다. 현재 적용 순서는 이 파일 하나입니다.
5. 서로 다른 기기에서 방 생성과 코드 참가, 위치·Ping·공유 목적지를 확인합니다. 익명 세션은 앱 데이터가 삭제되면 복구되지 않을 수 있습니다.

[Supabase publishable key 안내](https://supabase.com/docs/guides/getting-started/migrating-to-new-api-keys), [익명 인증 안내](https://supabase.com/docs/guides/auth/auth-anonymous). `service_role`, `sb_secret_...`, secret key는 절대로 모바일 앱에 넣지 마세요.

## 4. Mapbox 설정

1. [Mapbox Access Tokens](https://console.mapbox.com/account/access-tokens/)에서 앱 전용 **public** access token을 생성하거나 적절한 public token을 선택합니다.
2. 지도 스타일과 글꼴을 읽을 수 있도록 public scope `styles:read`, `fonts:read`를 포함합니다. SDK 다운로드용 `downloads:read`는 앱의 런타임 토큰에 필요하지 않습니다.
3. `pk.`로 시작하는 토큰을 `MAPBOX_ACCESS_TOKEN`에 넣습니다. `sk.` secret token은 넣지 않습니다.
4. 온라인 상태에서 앱의 **오프라인 지도**를 열고 현재 위치 주변 영역을 내려받은 다음 비행기 모드에서 전환을 확인합니다.

[Mapbox 토큰 scope 안내](https://docs.mapbox.com/accounts/guides/tokens/), [오프라인 지도 안내](https://docs.mapbox.com/help/dive-deeper/mobile-offline/).

## 5. 로컬 설정 파일

저장소 루트에서 다음을 실행합니다.

```bash
cp config/defines.example.json config/defines.local.json
```

`config/defines.local.json`의 `KAKAO_NATIVE_APP_KEY`에는 Kakao Developers의 Native app key, `SUPABASE_URL`에는 HTTPS Project URL, `SUPABASE_PUBLISHABLE_KEY`에는 publishable key, `MAPBOX_ACCESS_TOKEN`에는 `pk.` public token을 입력합니다. 파일은 `.gitignore`로 제외되지만 로컬 기기에서 안전하게 관리하세요. 키를 채우지 않아도 앱과 나침반은 실행되며 해당 서비스만 비활성화됩니다. 기존 개별 `--dart-define=이름=값`도 사용할 수 있습니다.

```json
{
  "KAKAO_NATIVE_APP_KEY": "발급받은_Native_app_key",
  "SUPABASE_URL": "https://프로젝트.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_...",
  "MAPBOX_ACCESS_TOKEN": "pk...."
}
```

## 6. 로컬 실행

Flutter 3.47 이상, Android SDK 36, Python 3가 필요합니다. iOS/iPadOS는 Mac, Xcode 26.1.1 이상과 CocoaPods가 필요합니다. connectivity_plus는 7.3.1, Android AGP는 8.12.1, Gradle은 8.14, Kotlin은 2.2.20으로 설정됩니다. 최초 체크아웃과 플랫폼 재생성 시:

```bash
bash tool/bootstrap.sh
flutter run --dart-define-from-file=config/defines.local.json
```

앱 상단 **설정 및 오프라인 지도 → 서비스 상태**에서 설정 형식과 런타임 상태를 확인합니다. `연결 인터페이스 있음`은 인터넷 연결 성공이 아니며, `초기화 완료`도 Kakao/Supabase/Mapbox의 실제 서버 인증 성공을 보증하지 않습니다.

### iPad 연결/위치 진단

- **Network 확인 중 / 상태 확인 실패**: unknown 상태입니다. Kakao 로드는 계속 시도하며 플러그인 실패를 오프라인으로 확정하지 않습니다.
- **Network 연결 없음**: 플러그인이 명시적 `none`을 보고했습니다. Wi-Fi OFF→ON 또는 앱 foreground 복귀 시 재조회합니다. 초기/복귀 조회는 0.5초·1.5초 뒤 최대 두 번 재시도합니다.
- **Kakao 인증/초기화 실패 / timeout**: Network와 별도 문제입니다. Native app key·플랫폼 등록을 확인하고 온라인 재시도를 누르세요.
- **Kakao lifecycle**: `enginePrepareRequested`는 호출 요청이고 `enginePrepared`/`engineActivated`는 SDK에서 관측한 상태입니다. prepared 상태 또는 인증 성공이 있으면 foreground·양수 크기에서 활성화합니다. 공식 지도 그리기 예제처럼 인증 성공 콜백이 오지 않더라도 실제 prepared 상태에서 진행할 수 있습니다. `addViews → addViewSucceeded → loaded`는 실제 delegate로 처리합니다. `SDK initialized`는 초기화 호출 완료이며 서버 인증 성공을 의미하지 않습니다.
- **prepareEngine return / Engine prepared / Engine active / Auth callback status**: 반환 Bool은 진단 값이고 `false`는 즉시 실패가 아닙니다. prepared/active는 `KMController.isEnginePrepared/isEngineActive` 실제 값입니다. auth callback은 `none/succeeded/failed`로 구분합니다. `getStateDescMessage()`의 데이터 형식과 민감정보 제외가 공식 문서에서 보장되지 않아 debug 빌드에서 원문을 일시적으로 읽고 존재 여부만 남깁니다. UI에는 boolean에서 만든 고정 summary만 표시하며 원문을 저장·전달·로그하지 않습니다.
- **Kakao timeout**: foreground 18초 동안 prepared/active 상태, 인증/addViews 콜백 진행이 없으면 `prepare timeout`입니다. 준비 또는 관련 콜백 진행 후 지도 생성이 완료되지 않으면 일반 지도 timeout으로 구분합니다. SDK 상태 확인은 준비 시도당 0.5/1.5/3/6/12/18초의 유한 snapshot만 사용합니다. native가 timeout과 재시도를 담당하는 iOS 뷰를 Flutter 18초 타이머가 중간에 종료하지 않습니다. background에서는 감시를 취소하고 foreground에서 다시 시작합니다.
- **Kakao 인증 코드/재시도**: `400` 요청 파라미터, `401` 인증 자격 증명, `403` 권한, `429` 할당량, `499` 인증 서버 통신 실패입니다. 실제 499와 recoverable prepare timeout만 0.5초·1.5초 지연의 공통 최대 두 번 예산으로 자동 재시도합니다. Bool false는 예산을 소비하지 않습니다. 종료된 인증 실패는 Wi-Fi/foreground 변화로 자동 반복하지 않으며 사용자가 재시도할 수 있습니다. 원문 `desc`는 수집하거나 표시하지 않습니다.
- **Expected / Runtime Bundle ID / Match**: Runtime 값은 설치된 앱의 `Bundle.main.bundleIdentifier`를 읽습니다. `no`이면 재서명된 실제 ID를 Kakao Developers의 플랫폼 등록과 대조하세요. 상수 Expected 값은 런타임 ID를 대신하지 않습니다. 키는 `key present / key missing`으로만 표시합니다.
- **Location 탐색 중**: 첫 fix가 15초를 넘겨도 탐색을 유지합니다. Wi-Fi 전용 iPad의 위치 수신과 정확도는 기기/환경 영향을 받으므로 실제 수신을 확인하세요. 실제 stream/권한/서비스/플러그인 오류는 별도로 표시합니다.
- **Supabase 초기화 실패**: `plugin / storage / network / timeout / authentication / configuration / unexpected` 분류를 확인합니다. 원문 예외·자격 증명은 표시하지 않습니다.
- debug 빌드는 `[passcom]` 이벤트에 인터페이스 enum, 네트워크 상태, SDK 상태, 권한/서비스/첫 fix/오류 분류만 기록합니다. 좌표·키/토큰·사용자 식별자는 기록하지 않습니다. release IPA에서는 이 진단 로그를 출력하지 않습니다.

Flutter 3.47은 UIScene engine 콜백에서 모든 플러그인과 커스텀 bridge를 등록해야 합니다. 부트스트랩은 이 AppDelegate와 Scene Manifest를 유지합니다. 참고: [Flutter UIScene migration](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate), [connectivity_plus 요구사항 및 제한](https://pub.dev/packages/connectivity_plus).

iOS bridge의 인증·foreground·크기·499 retry 정책은 SDK-independent `KakaoEngineLifecycle.swift`를 사용합니다. bootstrap은 이 소스와 AppDelegate를 하나의 generated compilation unit으로 합쳐 Xcode 템플릿 변경과 무관하게 포함합니다. Mac에서 CI와 같은 정책 테스트:

```bash
swiftc -parse-as-library platform_overrides/ios/KakaoEngineLifecycle.swift tool/test_kakao_lifecycle.swift -o /tmp/passcom-kakao-lifecycle-tests
/tmp/passcom-kakao-lifecycle-tests
```

공식 [KMController reference](https://apis.map.kakao.com/ios_v2/references/Classes/KMController.html), [지도 그리기 예제](https://apis.map.kakao.com/ios_v2/docs/getting-started/basics/04_drawmap/), [iOS 인증](https://apis.map.kakao.com/ios_v2/docs/getting-started/basics/02_auth/), [View Controls](https://apis.map.kakao.com/ios_v2/docs/getting-started/basics/01_view/) 흐름을 따릅니다. `prepareEngine() -> Bool`의 false를 fatal failure로 정의한 설명은 없으므로 이를 실패 판정으로 사용하지 않습니다. `addViewSucceeded`에서 현재 container bounds를 다시 적용하며, 첫 UIKit 레이아웃이 0×0일 때는 양수 크기를 기다립니다. Bundle ID의 Match는 영구 Expected ID와 비교한 값이며 Kakao Developers 등록을 조회한 결과는 아닙니다. 재서명된 Runtime ID를 등록했다면 Match가 no여도 그 자체로 인증 실패를 뜻하지 않습니다.

## 7. GitHub Actions Variables

[ybaf100/compass](https://github.com/ybaf100/compass) → **Settings → Secrets and variables → Actions → Variables → New repository variable**에서 아래 네 항목을 각각 추가합니다. 현재 workflow는 `vars.*`를 읽으므로 *Variables* 탭에 입력해야 빌드에 전달됩니다. 이 네 값은 모바일 바이너리에 포함되는 클라이언트 값이며, 서버용 비밀키를 입력하지 마세요.

| 변수 | 입력 값 |
| --- | --- |
| `KAKAO_NATIVE_APP_KEY` | Kakao Developers의 Native app key |
| `SUPABASE_URL` | Supabase Project URL (`https://...supabase.co`) |
| `SUPABASE_PUBLISHABLE_KEY` | `sb_publishable_...` |
| `MAPBOX_ACCESS_TOKEN` | `pk.` public token |

## 8. APK / IPA 빌드

로컬 Android:

```bash
flutter build apk --debug --dart-define-from-file=config/defines.local.json
```

Mac에서 iOS 시뮬레이터 또는 실제 기기 앱:

```bash
flutter build ios --simulator --debug --dart-define-from-file=config/defines.local.json
flutter build ios --release --no-codesign --dart-define-from-file=config/defines.local.json
```

GitHub Variables를 저장한 뒤 **Actions → verify passcom → 최신 실행 → Re-run all jobs**를 누르거나 작업 브랜치에 새 커밋을 push합니다. 해당 실행의 **Artifacts**에서 `passcom-android-debug`(APK), `passcom-ios-simulator`(시뮬레이터 ZIP), `passcom-ios-sideload-unsigned`(미서명 IPA가 담긴 ZIP)를 받습니다. Re-run 시점에 Variables가 다시 평가되는지 확실히 하려면 새 커밋으로 새 실행을 시작하세요. 미서명 IPA는 Apple 서명/프로비저닝이 없으므로 바로 설치되지 않습니다. 서명 도구가 Bundle ID를 바꾸면 Kakao 등록값과 재대조하세요.

CI는 두 번의 bootstrap 후 생성된 설정과 완성된 APK·iOS 앱·IPA의 이름/식별자를 검증합니다. 로컬에서도 같은 검사를 실행할 수 있습니다. APK 검사에는 Android SDK build-tools의 `aapt`가 필요하며 `ANDROID_HOME` 또는 PATH에서 자동으로 찾습니다.

```bash
python3 tool/verify_app_identity.py
python3 tool/verify_app_identity.py --apk build/app/outputs/flutter-apk/app-debug.apk
python3 tool/verify_app_identity.py --ios-app build/ios/iphonesimulator/Runner.app
python3 tool/verify_app_identity.py --ipa build/ios/ipa/passcom-ios-sideload-unsigned.ipa
```

## 9. 실제 기기 체크리스트

- iPhone/iPad 세로·가로 및 Android 전화·태블릿에서 화면 크기, 목적지 선택, 나침반 전체화면 스와이프를 확인합니다.
- 위치 권한 거부→허용, GPS 거리, heading 진북과 359°↔0° 회전, 앱 background→foreground 복귀를 확인합니다.
- Kakao 로딩·인증, 친구 marker, 방 참가, Ping, 공유 목적지, 친구 따라가기와 오래된 위치 표시를 두 기기에서 확인합니다.
- Mapbox 지역 다운로드·삭제·재시도, 비행기 모드에서 오프라인 지도와 Compass 유지, 온라인 복구 시 카메라 상태를 확인합니다.

## 10. 문제 해결

| 증상 | 확인할 것 |
| --- | --- |
| Kakao 401/403 또는 인증 실패 | Native app key, 카카오맵 사용 설정 ON, 실제 서명 APK의 Key Hash와 Android package, iOS Bundle ID를 확인. 사이드로드 도구가 ID를 바꾸지 않았는지도 확인 |
| Kakao 429 | 카카오맵 사용량/할당량 및 유료 API 설정 확인 |
| Supabase 친구방 사용 불가 | HTTPS URL, publishable key, Anonymous Sign-Ins, SQL migration 실행 결과, publication/Realtime, 네트워크 확인 |
| Mapbox 지도 없음 | `pk.` public token과 `styles:read`/`fonts:read` scope, 온라인에서 유효한 지역 다운로드, 현재 GPS가 해당 지역 안에 있는지 확인 |
| 지도 실패 중 나침반 | GPS 권한과 heading 센서, 저장된 목적지를 확인. 지도 서비스 설정과 별개로 Compass가 작동하도록 구성됨 |

서비스 상태 화면은 자격 증명 원문을 표시하지 않으며 설정 형식과 native engine/인증/로드 상태를 구분합니다. 실제 사용 가능 여부는 기기에서 지도 로딩, 방 연결, 지역 다운로드로 검증해야 합니다.
