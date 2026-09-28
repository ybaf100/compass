# 목적지 나침반

네이버 지도에서 목적지를 고르고, GPS 거리와 기기 방향 센서로 가리키는 Flutter 앱입니다. iOS, iPadOS, Android를 대상으로 합니다. 지도와 센서는 네이티브 SDK를 쓰고, 거리·방위각·화면은 하나의 Dart 코드베이스로 공유합니다.

## 실행

Flutter SDK(3.35 이상), Android SDK(36), iOS 개발용 Mac/Xcode 및 CocoaPods(iOS 빌드 시), Python 3가 필요합니다. 이 저장소의 `platform_overrides`는 `flutter create`로 생성된 프로젝트에 적용할 네이티브 센서 코드입니다. **최초 실행과 플랫폼 파일 재생성 시** 아래를 먼저 실행하세요.

```bash
bash tool/bootstrap.sh
flutter test
flutter analyze
flutter run --dart-define=NAVER_MAP_CLIENT_ID=발급받은_Client_ID
```

## 친구방 설정

친구방은 Supabase의 익명 Auth, Postgres, Realtime을 사용합니다. Supabase 프로젝트에서 **Anonymous Sign-Ins**를 켜고, `supabase/migrations/202609270001_rooms.sql`을 SQL Editor에 적용하세요. 이 마이그레이션은 Room·Member·Ping 테이블, 멤버만 읽을 수 있는 RLS 정책, 멤버십을 검사하는 쓰기 RPC, Realtime publication을 설정합니다. 서비스 역할 키를 앱에 넣지 마세요.

프로젝트 URL과 publishable key를 앱 실행 시 전달합니다.

```bash
bash tool/bootstrap.sh
flutter run \
  --dart-define=NAVER_MAP_CLIENT_ID=발급받은_Client_ID \
  --dart-define=SUPABASE_URL=https://프로젝트.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_... \
  --dart-define=MAPBOX_ACCESS_TOKEN=pk....
```

`SUPABASE_URL` 또는 `SUPABASE_PUBLISHABLE_KEY`가 비어 있으면 친구방 UI에서 설정 안내를 보여주며 개인 목적지는 그대로 작동합니다. 값은 저장소에 커밋하지 않습니다. Supabase 프로젝트 자체와 데이터베이스 마이그레이션은 별도로 준비해야 합니다.

## 오프라인 지도

Mapbox의 **public** access token (`pk.`)을 `MAPBOX_ACCESS_TOKEN` dart-define으로 주입합니다. secret token은 모바일 앱에 넣지 마세요. 토큰이 없으면 오프라인 지도만 비활성화되고 네이버 지도·나침반·친구방은 계속 사용할 수 있습니다. iOS 14 이상과 Android 23 이상이 필요합니다.

온라인일 때 상단 **오프라인 지도**에서 GPS 현재 위치 주변 5/20/50 km를 선택하고 용량을 추정한 뒤 내려받습니다. 실제 용량은 지역·줌·Mapbox 리소스에 따라 다릅니다. Mapbox 공식 Style Pack(`MAPBOX_STREETS`)과 Tile Region API를 사용하며 줌 0–15의 64각형 원형 영역을 저장합니다. 다운로드 중 진행률과 실패/재시도, 지역별 삭제 및 다운로드 용량 합계를 표시합니다. 겹친 타일과 공유 Style Pack 때문에 합계는 실제 앱의 물리적 저장 공간과 다를 수 있습니다. 타일 지역을 지워도 공유 Style Pack이나 다른 지역의 타일은 제거하지 않습니다.

연결이 끊기거나 네이버 지도 인증·로드가 실패하면 현재 GPS 위치를 포함하는 다운로드 지역이 있는 경우 Mapbox 지도만 전환합니다. 연결이 돌아오면 짧은 안정화 시간 뒤 네이버 지도를 다시 로드합니다. 나침반·개인 목적지·Room은 지도 위젯과 별도로 유지됩니다. 오프라인의 친구 위치와 공유 목적지는 마지막 동기화 정보로 명시하고, Ping 및 공유 목적지 변경은 연결이 돌아올 때까지 비활성화합니다. 마지막 Room 스냅샷의 유효 Ping은 30분이 지나면 사라집니다. 백그라운드 다운로드와 오프라인 변경 대기열은 지원하지 않습니다.

첫 친구방 사용 시 닉네임을 입력하면 익명 사용자 ID가 생성됩니다. 닉네임과 참가 중인 Room ID는 기기에 저장되고, 인증 세션은 Supabase SDK가 복원합니다. 방에서 나가면 즉시 로컬 위치 업로드와 구독을 중지합니다. 서버 나가기 요청에 실패하면 다음 연결에서 재시도합니다. 앱이 백그라운드에 있으면 위치를 업로드하지 않습니다. 친구 위치는 35초가 지나면 오래된 정보로 표시합니다.

위치는 기존 GPS 입력을 재사용하며 정확도 80m 이하에서만 전송합니다. 최소 2초 간격을 두고, 8m 이상 이동하거나 8초가 지나면 갱신합니다. Ping은 최근 20개 또는 30분 이내로 제한합니다. 친구 마커의 작은 이동은 짧게 보간하며, 먼 이동과 오래된 정보는 즉시 표시합니다.

네이버 클라우드 Maps에서 **Mobile Dynamic Map**을 신청한 후 Android 패키지 이름과 iOS Bundle ID를 모두 등록해야 합니다. 기본 Android 패키지 이름은 `com.example.destination_compass`입니다. 생성된 iOS Bundle ID는 `ios/Runner.xcodeproj/project.pbxproj`의 `PRODUCT_BUNDLE_IDENTIFIER`에서 확인하세요. 플랫폼 ID를 바꾼 경우 네이버 콘솔의 등록값과 일치시킵니다. Client ID는 `--dart-define`으로 주입하며 저장소에 넣지 않습니다. ID가 없어도 앱은 시작하고 이유를 보여주지만 지도는 나오지 않습니다.

Android:

```bash
flutter build apk --debug --dart-define=NAVER_MAP_CLIENT_ID=발급받은_Client_ID
```

iOS/iPadOS (Mac):

```bash
flutter build ios --simulator --debug --dart-define=NAVER_MAP_CLIENT_ID=발급받은_Client_ID
```

실기기 배포 시에는 서명과 provisioning profile을 구성해야 합니다. 기기의 권한 안내를 승인해야 GPS와 진북 방위각이 제공됩니다. 일부 iPad/Android 모델에는 나침반 센서가 없어 목적지 및 거리만 표시될 수 있습니다.

## 사용법

지도에서 원하는 곳을 터치하거나 길게 눌러 선택합니다. 위치 확인 카드에서 **목적지로 설정**을 누릅니다. 지도 상단의 내 위치 버튼으로 따라가기를 다시 켭니다. 하단 패널을 위로 끌면 전체화면 나침반으로, 아래로 끌면 지도로 돌아갑니다. 목적지 해제는 지도 상단 버튼이나 전체화면의 해제 버튼에서 가능합니다. 마지막 목적지는 기기에 저장됩니다.

## 구조

| 영역 | 책임 |
| --- | --- |
| `lib/core/location` | 권한 상태 및 GPS 스트림 |
| `lib/core/compass` | 네이티브 heading 채널 및 원형 노이즈 필터 |
| `lib/destination` | 목적지 모델, 저장, 거리·방위각, 상태 조정 |
| `lib/map` | MapProvider, 네이버/Mapbox SDK 어댑터 및 지도 전환 상태 |
| `lib/offline` | 다운로드 영역·메타데이터·Mapbox 타일 저장소 |
| `lib/ui` | 지도 화면, 스와이프 패널, 프레임 기반 화살표 애니메이션 |
| `platform_overrides` | Android 회전 벡터 및 iOS Core Location heading |

방위각은 진북 기준입니다. Android는 GPS 좌표로 자기편각을 보정하고, iOS는 Core Location trueHeading을 우선합니다. 보정할 GPS가 없거나 trueHeading이 제공되지 않으면 자기북 기준임을 화면에 알립니다. 지도 네트워크 오류 중에도 저장된 목적지와 새 GPS/센서 값은 별도로 유지됩니다.

지도 서비스는 Flutter용 `flutter_naver_map` 1.4.4를 **MapProvider 내부에서만** 사용합니다. 다른 지도 엔진으로 바꿀 때 `MapProvider` 구현을 추가합니다. 네트워크 연결 유형은 실제 인터넷 연결을 보증하지 않으므로 지도 로딩 시간 초과 및 인증 오류도 따로 표시합니다.

## 검증

`flutter test`, `flutter analyze`, `flutter build apk --debug`, `flutter build ios --simulator --debug`, `flutter build ios --release --no-codesign`이 CI에 설정돼 있습니다. 성공한 GitHub Actions 실행의 **Artifacts**에서 Android 디버그 APK(`compass-android-debug`), iOS 시뮬레이터 앱 ZIP(`compass-ios-simulator`), iPhone/iPad 실기기용 미서명 IPA(`compass-ios-sideload-unsigned`)를 다운로드할 수 있습니다. GitHub가 IPA를 한 번 더 ZIP으로 묶으므로 내려받은 ZIP에서 `.ipa` 파일을 꺼내세요.

`compass-ios-sideload-unsigned.ipa`는 arm64 iOS 실기기용 release 바이너리를 `Payload/Runner.app` 형식으로 묶은 것입니다. 서명 없이 직접 설치할 수는 없으며 SideStore 같은 사이드로드 앱에서 **IPA를 선택하고 본인 Apple 계정으로 서명**해야 합니다. 시뮬레이터 ZIP은 실기기에 설치할 수 없습니다. SideStore에서 비ASCII 앱 이름으로 App ID 등록 오류가 발생하지 않도록 사이드로드 IPA의 홈 화면 표시 이름만 `Compass`로 설정했습니다. IPA의 실제 설치·GPS·heading·지도 인증은 실기기에서 확인해야 합니다.

CI 빌드에서 온라인 지도·친구방·오프라인 지도를 사용하려면 저장소 **Settings → Secrets and variables → Actions → Variables**에 `NAVER_MAP_CLIENT_ID`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `MAPBOX_ACCESS_TOKEN`을 등록하고 빌드를 다시 실행하세요. 값이 없는 빌드도 컴파일되지만 해당 서비스는 동작하지 않습니다. 앱에 포함되는 값이므로 Supabase **service_role** 키나 Mapbox secret token은 절대 사용하지 마세요. 네이버 Maps에 등록한 Android 패키지 이름과 iOS Bundle ID가 실제 설치된 앱과 일치해야 합니다. 사이드로드 도구가 iOS Bundle ID를 다시 쓰면 네이버 인증에 사용할 등록값도 확인해야 합니다.

Room 테스트는 같은 가짜 저장소를 쓰는 두 클라이언트의 생성·참가·위치·Ping·공유 목적지·친구 추적·퇴장 흐름을 검증합니다. 실기기에서는 GPS 권한 거부/재허용, 지도 인증과 핀, 가로 모드, 359°↔0° 회전, 자기장 교란, 고주사율 애니메이션, 서로 다른 기기의 Room 동기화와 재연결을 확인하세요.
