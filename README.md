# passcom

passcom은 지도에서 목적지를 지정하고 기기의 방향을 기준으로 목적지를 가리키는 크로스플랫폼 목적지 나침반 앱입니다. iOS, iPadOS, Android를 대상으로 합니다. 지도와 센서는 네이티브 SDK를 쓰고, 거리·방위각·화면은 하나의 Flutter/Dart 코드베이스로 공유합니다.

| 기능 | 기술 |
| --- | --- |
| 온라인 지도 | Kakao Maps |
| 오프라인 지도 | Mapbox |
| 실시간 친구방 | Supabase |
| 나침반 | 네이티브 기기 센서 |

홈 화면 앱 이름과 앱 내 브랜드명은 모두 `passcom`입니다. Android applicationId/namespace와 iOS/iPadOS Bundle ID는 `com.ybaf100.compass`, 내부 Flutter 프로젝트명은 `destination_compass`를 유지합니다. 부트스트랩을 다시 실행해도 이름과 식별자는 동일합니다.

앱 아이콘은 제공된 우주·나침반 이미지입니다. iPhone/iPad AppIcon과 Android density별/Adaptive launcher 리소스를 `platform_overrides/icons`에 보관하고 bootstrap마다 적용합니다. `python3 tool/app_icons.py --verify-applied`로 적용 누락을 검사합니다. 원본 디자인을 바꾸지 않고 플랫폼별 크기로 축소하며, 아이콘 재생성만 Pillow가 필요합니다 (`python3 tool/app_icons.py --source 이미지경로`). 일반 bootstrap/CI에는 추가 패키지가 필요하지 않습니다.

**실제 서비스 연결과 실기기 빌드:** [SETUP.md](SETUP.md) — 앱 식별자, Kakao/Supabase/Mapbox 발급 순서, Android Key Hash, 로컬 설정 파일, GitHub Actions Variables, APK/IPA 다운로드, 기기 점검 및 문제 해결.

## 실행

Flutter SDK(3.47 이상), Android SDK(36), iOS 개발용 Mac/Xcode 및 CocoaPods(iOS 빌드 시), Python 3가 필요합니다. 이 저장소의 `platform_overrides`는 `flutter create`로 생성된 프로젝트에 적용할 네이티브 센서 코드입니다. **최초 실행과 플랫폼 파일 재생성 시** 아래를 먼저 실행하세요.

```bash
bash tool/bootstrap.sh
flutter test
flutter analyze
cp config/defines.example.json config/defines.local.json
# config/defines.local.json에 발급받은 클라이언트 값을 입력한 뒤
flutter run --dart-define-from-file=config/defines.local.json
```

## 친구방 설정

친구방은 Supabase의 익명 Auth, Postgres, Realtime을 사용합니다. Supabase 프로젝트에서 **Anonymous Sign-Ins**를 켜고, `supabase/migrations/202609270001_rooms.sql`을 SQL Editor에 적용하세요. 이 마이그레이션은 Room·Member·Ping 테이블, 멤버만 읽을 수 있는 RLS 정책, 멤버십을 검사하는 쓰기 RPC, Realtime publication을 설정합니다. 서비스 역할 키를 앱에 넣지 마세요.

프로젝트 URL과 publishable key를 앱 실행 시 전달합니다.

```bash
bash tool/bootstrap.sh
flutter run \
  --dart-define=KAKAO_NATIVE_APP_KEY=발급받은_Native_app_key \
  --dart-define=SUPABASE_URL=https://프로젝트.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_... \
  --dart-define=MAPBOX_ACCESS_TOKEN=pk....
```

`SUPABASE_URL` 또는 `SUPABASE_PUBLISHABLE_KEY`가 비어 있으면 친구방 UI에서 설정 안내를 보여주며 개인 목적지는 그대로 작동합니다. 값은 저장소에 커밋하지 않습니다. Supabase 프로젝트 자체와 데이터베이스 마이그레이션은 별도로 준비해야 합니다.

## 오프라인 지도

Mapbox의 **public** access token (`pk.`)을 `MAPBOX_ACCESS_TOKEN` dart-define으로 주입합니다. secret token은 모바일 앱에 넣지 마세요. 토큰이 없으면 오프라인 지도만 비활성화되고 카카오 지도·나침반·친구방은 계속 사용할 수 있습니다. 이 프로젝트는 iOS/iPadOS 15 이상과 Android API 24 이상을 대상으로 합니다.

Android 부트스트랩은 네이티브 Kakao Maps SDK v2와 Mapbox SDK에 AGP 8.12.1, Gradle 8.14, Kotlin 2.2.20을 생성된 프로젝트에 지정합니다. `connectivity_plus 7.3.1`을 사용하며 iOS 빌드에는 Xcode 26.1.1 이상이 필요합니다.

온라인일 때 상단 **설정 및 오프라인 지도 → 오프라인 지도**에서 GPS 현재 위치 주변 5/20/50 km를 선택하고 용량을 추정한 뒤 내려받습니다. 실제 용량은 지역·줌·Mapbox 리소스에 따라 다릅니다. Mapbox 공식 Style Pack(`MAPBOX_STREETS`)과 Tile Region API를 사용하며 줌 0–15의 64각형 원형 영역을 저장합니다. 다운로드 중 진행률과 실패/재시도, 지역별 삭제 및 다운로드 용량 합계를 표시합니다. 겹친 타일과 공유 Style Pack 때문에 합계는 실제 앱의 물리적 저장 공간과 다를 수 있습니다. 타일 지역을 지워도 공유 Style Pack이나 다른 지역의 타일은 제거하지 않습니다.

연결이 끊기거나 카카오 지도 인증·로드가 실패하면 현재 GPS 위치를 포함하는 다운로드 지역이 있는 경우 Mapbox 지도만 전환합니다. 연결이 돌아오면 짧은 안정화 시간 뒤 카카오 지도를 다시 로드합니다. 나침반·개인 목적지·Room은 지도 위젯과 별도로 유지됩니다. 오프라인의 친구 위치와 공유 목적지는 마지막 동기화 정보로 명시하고, Ping 및 공유 목적지 변경은 연결이 돌아올 때까지 비활성화합니다. 마지막 Room 스냅샷의 유효 Ping은 30분이 지나면 사라집니다. 백그라운드 다운로드와 오프라인 변경 대기열은 지원하지 않습니다.

첫 친구방 사용 시 닉네임을 입력하면 익명 사용자 ID가 생성됩니다. 닉네임과 참가 중인 Room ID는 기기에 저장되고, 인증 세션은 Supabase SDK가 복원합니다. 방에서 나가면 즉시 로컬 위치 업로드와 구독을 중지합니다. 서버 나가기 요청에 실패하면 다음 연결에서 재시도합니다. 앱이 백그라운드에 있으면 위치를 업로드하지 않습니다. 친구 위치는 35초가 지나면 오래된 정보로 표시합니다.

위치는 기존 GPS 입력을 재사용하며 정확도 80m 이하에서만 전송합니다. 최소 2초 간격을 두고, 8m 이상 이동하거나 8초가 지나면 갱신합니다. Ping은 최근 20개 또는 30분 이내로 제한합니다. 친구 마커의 작은 이동은 짧게 보간하며, 먼 이동과 오래된 정보는 즉시 표시합니다.

Kakao Developers에서 앱 이름을 `passcom`으로 만들고 **카카오맵 → 사용 설정**을 켠 뒤 Native app key에 Android 패키지 이름, APK 서명 Key Hash, iOS Bundle ID를 등록합니다. 패키지/Bundle ID는 `com.ybaf100.compass`입니다. 상세 단계는 [SETUP.md](SETUP.md)에 있습니다. 키가 없어도 앱은 시작하고 이유를 보여주지만 온라인 지도는 나오지 않습니다.

Android:

```bash
flutter build apk --debug --dart-define=KAKAO_NATIVE_APP_KEY=발급받은_Native_app_key
```

iOS/iPadOS (Mac):

```bash
flutter build ios --simulator --debug --dart-define=KAKAO_NATIVE_APP_KEY=발급받은_Native_app_key
```

실기기 배포 시에는 서명과 provisioning profile을 구성해야 합니다. 기기의 권한 안내를 승인해야 GPS와 진북 방위각이 제공됩니다. 일부 iPad/Android 모델에는 나침반 센서가 없어 목적지 및 거리만 표시될 수 있습니다.

## 사용법

지도에서 원하는 곳을 터치하거나 길게 눌러 선택합니다. 위치 확인 카드에서 **목적지로 설정**을 누릅니다. 지도 상단의 내 위치 버튼으로 따라가기를 다시 켭니다. 하단 패널을 위로 끌면 전체화면 나침반으로, 아래로 끌면 지도로 돌아갑니다. 개인 목적지 해제는 지도 상단 버튼을 사용하고, 내 목적지·공유 목적지·친구 따라가기 전환은 친구방 UI에서 합니다. 마지막 목적지는 기기에 저장됩니다.

Compass는 접힘·확장 중간·전체화면 모두 **방향 화살표와 거리만** 표시합니다. 목적지 이름, 모드, notice, 북 기준 설명, 상세 정보와 해제 버튼은 Compass에서 표시하지 않습니다. 목적지 없음과 방향 센서 사용 불가만 간단히 안내합니다. 친구의 오래된 위치 정보는 친구방·친구 상세 UI에서 확인합니다.

Kakao 마커의 보이는 지름은 목적지 22, 친구/오래된 친구/Ping 18, candidate 16 logical pixels입니다. 내 위치는 16 지름의 중심 점과 방향 cone를 40 크기 canvas에 그립니다. 친구 마커는 투명한 44 크기 canvas로 터치 영역을 확보합니다. Android에서는 이미 density를 반영한 bitmap에 SDK density scaling을 다시 적용하지 않습니다. **Mapbox 마커 스타일과 크기는 변경하지 않습니다.** 실제 터치 범위와 가독성은 기기에서 확인해야 합니다.

내 위치 방향은 기존 filteredHeading을 optional provider capability로 전달합니다. Kakao bridge는 최신 값만 최대 초당 20회 전달하고 동시에 한 요청만 실행하며, 친구/Ping/목적지 overlay는 재전송하지 않습니다. native SDK의 카메라 bearing을 읽어 `normalize(deviceHeading - cameraBearing)`을 적용합니다. iOS의 반시계 radians와 Android의 시계 radians는 공통 시계 degrees로 변환합니다. `Default`의 화면 위쪽 billboard 기준에 계산한 상대 각도를 적용하여 SDK의 세계 좌표 회전과 중복 보정하지 않습니다. 최단 각도 기반 짧은 90ms 회전을 적용하고, 지도 이동 중에만 CADisplayLink/Choreographer에서 카메라 방향을 갱신합니다. pause/dispose에서 callback을 정리합니다. 지도 회전 보정과 359°/0° 방향은 실기기 재검증 대상입니다.

## 구조

| 영역 | 책임 |
| --- | --- |
| `lib/core/location` | 권한 상태 및 GPS 스트림 |
| `lib/core/compass` | 네이티브 heading 채널 및 원형 노이즈 필터 |
| `lib/destination` | 목적지 모델, 저장, 거리·방위각, 상태 조정 |
| `lib/map` | MapProvider, Kakao native PlatformView/Mapbox SDK 어댑터 및 지도 전환 상태 |
| `lib/offline` | 다운로드 영역·메타데이터·Mapbox 타일 저장소 |
| `lib/ui` | 지도 화면, 스와이프 패널, 프레임 기반 화살표 애니메이션 |
| `platform_overrides` | Android/iOS Kakao Maps SDK v2 브리지, 회전 벡터 및 Core Location heading |

방위각은 진북 기준입니다. Android는 GPS 좌표로 자기편각을 보정하고, iOS는 Core Location trueHeading을 우선합니다. 보정할 GPS가 없거나 trueHeading이 제공되지 않으면 자기북을 사용하므로 오차가 생길 수 있습니다. Compass에는 북 기준 설명을 표시하지 않습니다. 지도 네트워크 오류 중에도 저장된 목적지와 새 GPS/센서 값은 별도로 유지됩니다.

온라인 지도는 공식 Kakao Maps Android v2 `2.15.2` 및 iOS v2 `2.12.19`를 네이티브 PlatformView로 표시합니다. Dart의 `KakaoMapProvider`와 별도 브리지 바깥에는 SDK 타입이 노출되지 않습니다. 오프라인 지도는 Mapbox입니다. 네트워크 연결 유형은 실제 인터넷 연결을 보증하지 않으므로 지도 로딩 시간 초과 및 인증 오류도 따로 표시합니다.

네트워크 상태는 `unknown / available / unavailable`입니다. 플러그인 조회·스트림 예외와 빈 결과는 unknown이며, 명시적 `none`만 unavailable로 처리합니다. unknown도 Kakao 지도 로드를 시도합니다. Wi-Fi 복구와 앱 resume에서 상태를 재조회하고, 초기/복귀 조회는 필요할 때 0.5초·1.5초 뒤 최대 두 번 재확인합니다. 최신 스트림 이벤트는 오래된 비동기 조회 결과보다 우선합니다. Kakao 인증/초기화 실패와 18초 로드 timeout은 별도 상태이며, 기존 오프라인 전환 지연과 카메라 보존을 유지합니다.

iOS는 UIScene의 `didInitializeImplicitFlutterEngine`에서 플러그인·Heading 채널·Kakao PlatformView를 등록합니다. CI는 iPad 시뮬레이터에서 connectivity, 위치 권한 조회, SharedPreferences, Heading 채널, Kakao PlatformView의 실제 등록까지 확인합니다. 위치 권한 허용 후 첫 GPS fix가 15초 늦어져도 스트림을 끊지 않고 탐색/재시도 상태를 유지합니다. 서비스 상태는 네트워크·SDK·위치 오류를 분리하고 키/좌표/개인 식별자를 표시하지 않습니다.

iPad smoke CI는 verbose 출력과 12분 launch 제한을 사용합니다. 테스트가 시작되기 전에 simulator/VM-service 연결이 멈춘 경우에만 선택한 시뮬레이터를 다시 시작해 한 번 재시도합니다. assertion/plugin 실패는 재시도로 숨기지 않으며, 실제 기기 인증/지도 로드를 검증하는 테스트는 아닙니다.

## 검증

Kakao iOS는 SDK prepared 상태 또는 인증 성공, foreground, 유효한 container 크기를 확인해 engine을 활성화합니다. `prepareEngine()` 반환 Bool은 진단 값이며 `false`만으로 실패하지 않습니다. 서비스 상태에서 실제 engine prepared/active, prepare return, auth callback, lifecycle 단계, 인증 코드와 설치 Bundle ID를 확인할 수 있습니다. 실제 499와 진행 없는 prepare timeout만 공통 예산으로 최대 두 번 자동 재시도하며, 종료된 인증 오류는 네트워크/앱 복귀로 반복하지 않습니다. CI는 production의 SDK-independent Swift 정책도 별도로 테스트합니다.

같은 브랜치에서 새 CI가 시작되면 이전 실행은 자동 취소됩니다. push와 PR 이벤트를 같은 concurrency 그룹으로 묶고, 다른 브랜치/포크의 실행은 독립적으로 유지합니다.

`flutter test`, `flutter analyze`, `flutter build apk --debug`, `flutter build ios --simulator --debug`, `flutter build ios --release --no-codesign`이 CI에 설정돼 있습니다. 부트스트랩 두 번 실행 후 이름/식별자를 검사하고, 완성된 APK·시뮬레이터 앱·IPA에서도 `passcom` 이름과 `com.ybaf100.compass` 식별자를 검증합니다. 성공한 GitHub Actions 실행의 **Artifacts**에서 Android 디버그 APK(`passcom-android-debug`), iOS 시뮬레이터 앱 ZIP(`passcom-ios-simulator`), iPhone/iPad 실기기용 미서명 IPA(`passcom-ios-sideload-unsigned`)를 다운로드할 수 있습니다. GitHub가 IPA를 한 번 더 ZIP으로 묶으므로 내려받은 ZIP에서 `.ipa` 파일을 꺼내세요.

`passcom-ios-sideload-unsigned.ipa`는 arm64 iOS 실기기용 release 바이너리를 `Payload/Runner.app` 형식으로 묶은 것입니다. 일반 iOS 빌드와 동일하게 표시 이름과 CFBundleName은 `passcom`, Bundle ID는 `com.ybaf100.compass`입니다. 패키징 과정에서 이름을 덮어쓰지 않습니다. 서명 없이 직접 설치할 수는 없으며 SideStore 같은 사이드로드 앱에서 **IPA를 선택하고 본인 Apple 계정으로 서명**해야 합니다. 시뮬레이터 ZIP은 실기기에 설치할 수 없습니다. IPA의 실제 설치·GPS·heading·지도 인증은 실기기에서 확인해야 합니다.

CI 빌드에서 온라인 지도·친구방·오프라인 지도를 사용하려면 저장소 **Settings → Secrets and variables → Actions → Variables**에 `KAKAO_NATIVE_APP_KEY`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `MAPBOX_ACCESS_TOKEN`을 등록하고 빌드를 다시 실행하세요. 값이 없는 빌드도 컴파일되지만 해당 서비스는 동작하지 않습니다. 앱에 포함되는 값이므로 Supabase **service_role** 키나 Mapbox secret token은 절대 사용하지 마세요. Kakao에 등록한 Android 패키지/서명 Key Hash와 iOS Bundle ID가 실제 설치된 앱과 일치해야 합니다. 사이드로드 도구가 iOS Bundle ID를 다시 쓰면 등록값도 확인해야 합니다.

Room 테스트는 같은 가짜 저장소를 쓰는 두 클라이언트의 생성·참가·위치·Ping·공유 목적지·친구 추적·퇴장 흐름을 검증합니다. 실기기에서는 GPS 권한 거부/재허용, 지도 인증과 핀, 가로 모드, 359°↔0° 회전, 자기장 교란, 고주사율 애니메이션, 서로 다른 기기의 Room 동기화와 재연결을 확인하세요.
