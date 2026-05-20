# Architecture Decisions

이 문서는 코드 레벨에서 자동 차단할 수 없는 **구조적 결정**을 기록한다. 새 기능 추가 시
이 결정을 위반하지 말 것.

## D1. 메뉴바 라벨은 AppKit `NSStatusItem` 직접 제어 (SwiftUI MenuBarExtra 폐기)

- **결정**: `App.swift` 가 `NSApplication.shared.run()` 직접. 메뉴바 라벨은 `StatusItemController`
  (AppKit) 가 단일 진입점.
- **이유**:
  - SwiftUI `MenuBarExtra` label 안에서 `Image(nsImage: computed)` 패턴은 매 body 평가마다
    새 NSImage 인스턴스를 생성, SwiftUI 가 view diff 못 함 → 메뉴바가 stale.
  - SwiftUI `App` + LSUIElement=YES 조합에서 macOS 26 가 AppDelegate 콜백을 호출하지
    않는 케이스 발견.
- **하지 말 것**: SwiftUI `MenuBarExtra`, `Image(nsImage: <computed>)` 메뉴바 직접 사용.
- **해도 됨**: SwiftUI 콘텐츠는 popover/window 내부에 `NSHostingController.sized(...)` 로
  호스팅 (드롭다운, 설정 창).

## D2. 모든 `NSHostingController` 는 `.sized(_:)` factory 사용

- **결정**: `NSHostingController.sized(rootView)` 만 사용. 생성자 직접 호출 금지.
- **이유**: macOS 13+ default 는 `host.preferredContentSize` 를 SwiftUI ideal size 로 자동
  채택하지 않음. `(0,0)` 이 되어 NSPopover anchor 가 화면 중앙으로 fallback.
- **차단**: `NSHostingController(rootView:` 직접 사용을 grep CI 룰로 거부할 수 있음.

## D3. 의존성 라이프사이클은 `AppDelegate.applicationDidFinishLaunching` 안에서 단일 순서

- **결정**: 도메인 객체 init 순서:
  1. `AccountManager()`
  2. `manager.reload()`
  3. `UsageMonitor(accountManager: manager)`
  4. `AppSettingsStore()`
  5. `StatusItemController(...)`
  6. `monitor.start()`
- **추가 가드**: `UsageMonitor` 가 `AccountManager.$accounts` 변경을 sink 해서 자동
  cached snapshots 재로드 — init 순서가 흔들려도 결과적으로 정상 동작.
- **이유**: 과거에 monitor 가 manager.reload 전에 init 되어 cached usage.json 미로드, 라벨에
  "--" 표시되는 버그 발생.

## D4. 메뉴바 라벨 색상은 NSImage 픽셀로 그림 (SwiftUI Text foregroundColor 무시됨)

- **결정**: 메뉴바 라벨의 색상 정보는 `StatusIconRenderer.renderStatusBar(...)` 가 만드는
  NSImage 안에 직접 픽셀로 그림. `isTemplate = false` 로 메뉴바 vibrancy 회피.
- **이유**: macOS 메뉴바는 SwiftUI Text 의 foregroundColor 를 monochrome 처리.
- **하지 말 것**: 메뉴바 라벨에 SwiftUI Text/Label 직접 사용 (색상 손실).

## D5. NSImage 그리기는 `NSImage(size:flipped:drawingHandler:)` 사용

- **결정**: `lockFocus + unlockFocus` 패턴 폐기.
- **이유**: `lockFocus` 는 representation 이 lazy 생성 + run loop race 가능. macOS 26 +
  NSStatusItem 조합에서 픽셀 데이터가 비어있는 상태로 button.image 에 set 되는 케이스 발생.
- **권장 패턴**: `NSImage(size:flipped:false) { _ in /* draw */; return true }`.

## D6. Startup self-check 로 메뉴바 visibility 회귀 즉시 감지

- **결정**: `StatusItemController.scheduleSelfCheck()` 가 1초 후 button.image.size 검사.
  width < 10 또는 height < 10 시 ERROR 로깅.
- **이유**: 메뉴바 visibility 회귀는 시각 검증 없이는 발견이 어려움. 자동 self-check 로
  로그에서 즉시 드러남.
- **운영**: `log show --info --predicate 'subsystem == "com.inchan.claude-code-menubar"' --last 1m | grep SELF-CHECK`

## D7. 활성 Claude credentials 는 `ClaudeLiveCredentials` 단일 정의원으로만 read

- **결정**: 활성 OAuth 토큰/credentials 를 읽는 모든 경로는 `ClaudeLiveCredentials.readRaw()` 통과.
  `ClaudeCredentialsFile().readRaw()` 직접 호출 금지 (helper 내부 fallback 외).
- **이유**: macOS Claude Code 는 토큰 refresh / 새 계정 로그인 시 **Keychain 만 갱신**하고
  `~/.claude/.credentials.json` 파일을 stale 또는 부재 상태로 남기는 동작이 관찰됨.
  파일만 읽으면:
  - import 시 새 계정 로그인 직후 `readRaw` throw → import 실패
  - polling 시 stale 토큰으로 영구 401
- **단일 정의원**: Keychain 우선 → 파일 fallback. 양쪽 부재 시 `notFound` throw.
- **소스 로깅**: helper 가 매 read 시 `[CRED-SRC] keychain|file|none` 을 로깅 → 회귀 즉시 진단.
- **차단**: `grep -rn "ClaudeCredentialsFile().readRaw\|ClaudeCredentialsFile()" Sources/`
  결과가 helper 자체를 제외하고 0 이어야 함.
- **WRITE 정책 (스위치 시)**: read 가 Keychain 우선이므로, 활성 자료 교체는 **파일 +
  Keychain 둘 다** 갱신해야 한다. 한 쪽만 갱신되면:
  - 파일만 갱신: `ClaudeLiveCredentials` 가 stale Keychain 토큰을 읽어 폴링이 **이전
    계정의 사용량을 새 계정 카드 자리에 표시** (관찰된 회귀)
  - Keychain만 갱신: Claude Code CLI 가 파일을 우선 보는 경로에서 stale
- **WRITE 구현**: `SwitchTransaction.executeLocked` 의 교체 + 검증 + rollback 세 곳에서
  `ClaudeCredentialsFile.writeRaw` 와 `ClaudeKeychainCredentials.writeRaw` 를 쌍으로 호출.
  검증은 `ClaudeKeychainCredentials.readRaw()` 로 expiresAt 일치도 확인.

## D8. 비활성 계정도 토큰 자동 refresh — `ClaudeOAuthRefresh`

- **결정**: 비활성 계정의 stale access_token 도 `refresh_token` 으로 자동 재발급. 비공식 OAuth endpoint 사용.
- **이유**: 비활성 계정은 스위치 전엔 Claude Code 가 토큰을 갱신할 수 없어 expiresAt 도달 후 영구 401 → 사용량 카드 stale.
  `~/.claude/projects/*.jsonl` 로컬 로그 파싱은 계정 식별자 부재로 다중 계정 매핑 불가.
- **endpoint**: `https://console.anthropic.com/v1/oauth/token` (1차) → `https://claude.ai/v1/oauth/token` (fallback).
  실측: console 이 429 던지는 동안 claude.ai 가 200 응답하는 케이스 다수 — endpoint 별 rate limit 분리됨.
  fallback 조건: transport / 5xx / 429.
- **client_id**: `9d1c250a-e61b-44d9-88ed-5944d1962f5e` (Claude Code 공식 client, 5+ 독립 소스 교차 검증).
- **rotation**: 응답에 새 `refresh_token` 있으면 snapshot 즉시 갱신, 없으면 기존 유지 (`rotation fallback`).
- **trigger**: `UsageMonitor.refresh()` 가 (a) expiresAt - 5분 미만이면 사전 호출, (b) `/api/oauth/usage` 401 시 1회 retry.
- **race 차단**: `refreshInFlight: Set<AccountID>` 로 per-account 직렬화. 활성 계정의 `~/.claude/.credentials.json` 은 절대 안 건드림 (Claude Code 와 race 회피, snapshot store 만 갱신).
- **kill switch**: `settings.useAutoRefresh` (default true). OFF 시 기존 동작 (스위치 시점 토큰만 사용).
- **장애 표시**: refresh 가 `invalid_grant` 면 `AccountError.invalidGrant` 로 UI 표시 + 5분 backoff. 사용자가 해당 계정으로 스위치 후 Claude Code 사용 → 새 토큰 자동 import.

## D9. lastError 는 `AccountError` enum (stringly-typed 금지)

- **결정**: `UsageMonitor.lastError` 의 값은 `AccountError` enum (`keychainDenied / unauthorized / invalidGrant / rateLimited / other(String)`).
- **이유**: 옛 String 키 (`"keychain_denied"` 등) 비교는 오타 시 무음 버그 발생. enum 으로 컴파일 타임 보장.
- **`.other(String)`**: 분류되지 않은 transport/decode 에러는 메시지 그대로 노출 — UI 가 "조회 실패: …" 형식으로 표시.

## 검증 명령

```sh
# 빌드 후 self-check 결과
log show --info --predicate 'subsystem == "com.inchan.claude-code-menubar"' --last 1m | grep SELF-CHECK

# NSHostingController 직접 사용 적발
grep -rn "NSHostingController(rootView:" Sources/

# SwiftUI MenuBarExtra 사용 적발
grep -rn "MenuBarExtra" Sources/

# lockFocus 패턴 적발
grep -rn "lockFocusFlipped\|\.lockFocus" Sources/

# Live credentials 단일 정의원 위반 적발 (helper 자체 제외)
grep -rn "ClaudeCredentialsFile()" Sources/ \
    | grep -v "ClaudeLiveCredentials.swift\|ClaudeCredentialsFile.swift"
# 결과: SwitchTransaction 의 self.credFile = ClaudeCredentialsFile() (쓰기 전용) — 허용

# CRED-SRC 로깅 — 런타임에 어느 소스에서 읽었는지 확인
log show --info --predicate 'subsystem == "com.inchan.claude-code-menubar"' --last 5m | grep CRED-SRC

# 스위치 시 Keychain 쓰기 누락 적발 — 파일 write 와 Keychain write 가 쌍으로 호출되는지
grep -n "credFile.writeRaw\|ClaudeKeychainCredentials.writeRaw" \
    Sources/ClaudeCodeMenubar/Core/SwitchTransaction.swift
# 결과: writeRaw 쌍이 같은 do 블록에 함께 등장해야 함 (교체 + rollback 양쪽)
```
