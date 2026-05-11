# CCMeter

macOS 메뉴바에서 Claude Code 계정을 빠르게 전환하고, 계정별 5h/7d 사용량을 한눈에 확인합니다.

<p align="center">
  <img src="docs/screenshots/popover.jpg" alt="CCMeter popover" height="380">
  &nbsp;
  <img src="docs/screenshots/demo.gif" alt="CCMeter demo: menubar → popover → settings" height="380">
</p>

> 메뉴바 라벨에는 활성 계정 이니셜, 5시간 세션 사용량 `S`, 7일 주간 사용량 `W` 가 표시됩니다. 라벨을 클릭하면 등록된 모든 계정의 사용량·리셋 시각·1-클릭 전환을 popover 로 제공합니다. 설정 창에서는 계정 추가/삭제, 표시 형식(숫자/진행바), 임계치 색상, 단축키, 시스템 옵션을 조정할 수 있습니다.

## 기능

- **계정 추가** — 현재 활성 Claude Code 계정 import 또는 `claude auth login` 새 로그인
- **계정 스위칭** — `~/.claude.json` 의 `oauthAccount` + `~/.claude/.credentials.json` 원자 교체. Claude Code CLI 실행 중이면 자동 차단
- **사용량 표시** — 5시간 세션 / 7일 주간 윈도우, 리셋까지 남은 시간, 임계치 색상
- **메뉴바 라벨** — 활성 계정 이니셜 + 결정적 컬러 도트 + `S: nn%` + `W: nn%`

## 빌드

```sh
make app           # .build/release 빌드 → "build/CCMeter.app" 생성 + codesign
make install       # ~/Applications/ 에 설치
make run           # 빌드 후 실행
make clean         # 산출물 정리
```

요구 사항: macOS 13+, Swift 6.0+, 빌드 도구 `make`.

코드 사인 인증서가 없으면 ad-hoc 서명되며, 매 빌드마다 Keychain 권한 프롬프트가 뜹니다. 안정 서명을 원하면 `make setup-cert` 로 self-signed 인증서를 한 번 등록하세요.

## 저장 구조

자체 저장소(`~/.ccmeter/`)만 사용하며 다른 도구의 데이터를 수정하지 않습니다.

```
~/.ccmeter/
├── accounts.json                # 등록된 계정 목록 (id, label, color, email, accountUuid, ...)
├── snapshots/<id>/
│   ├── claude-config.json       # ~/.claude.json 의 oauthAccount 백업
│   ├── claude-credentials.json  # ~/.claude/.credentials.json 백업
│   └── usage.json               # 마지막 사용량 스냅샷
├── backups/                     # 활성 자료의 timestamp 백업 (최근 5개)
├── settings.json                # 폴링 간격, 임계치 등
└── .lock                        # flock 단일 진입
```

> 구버전(`~/.cc-account-manager/`)이 남아있으면 첫 실행 시 자동으로 `~/.ccmeter/` 로 이동합니다.
> 신버전 디렉터리가 이미 있으면 마이그레이션은 건너뜁니다.

스위치 트랜잭션은 다음 순서로 진행됩니다.

1. `flock` 단일 진입 (`~/.ccmeter/.lock`)
2. Claude Code CLI 실행 여부 확인 — 실행 중이면 차단
3. 활성 자료(`~/.claude.json` + `~/.claude/.credentials.json`) timestamp 백업
4. 대상 자료를 atomic write(tmp + fsync + rename)로 교체
5. 검증 (accountUuid + expiresAt 일치)
6. 실패 시 백업으로 자동 복원

## 사용량 API (비공식)

`GET https://api.anthropic.com/api/oauth/usage`

- 인증: `Authorization: Bearer <claudeAiOauth.accessToken>`
- 헤더: `anthropic-beta: oauth-2025-04-20`, `anthropic-version: 2023-06-01`
- 응답: `{five_hour:{utilization, resets_at}, seven_day:{utilization, resets_at}}`
- 429: `Retry-After` 헤더 또는 본문 `retry_after` 존중 (지수 백오프 X, 서버 지시값 사용)

> 이 엔드포인트는 Anthropic 공식 API 문서에 등재되지 않은 비공식 OAuth 전용 엔드포인트입니다.
> Anthropic 측 변경 시 사용량 표시는 동작하지 않을 수 있습니다. 계정 스위치는 영향받지 않습니다.

## 키보드/단축키

- 메뉴 열고 `q` — 앱 종료

## 알려진 제약

- Keychain 의 `Claude Code-credentials` 항목은 직접 건드리지 않습니다. 환경에서 관찰된 동작상 `.credentials.json` 파일 교체만으로 Claude Code 가 새 토큰을 인식합니다 (Linux/macOS 모두).
- `claude auth login` 은 PTY 가 필요하므로 Terminal.app 을 띄워 실행한 뒤, 사용자가 종료하면 메뉴에서 “Import current” 를 눌러 등록합니다.
- 메뉴바 라벨은 macOS 13+ `MenuBarExtra` 가 아니라 AppKit `NSStatusItem` 직접 제어 (자세한 설계 결정은 [ARCHITECTURE.md](ARCHITECTURE.md) 참조).

## 런타임 검증

빌드 후 self-check + 런타임 로그로 가시성과 토큰 소스를 검증할 수 있습니다.

```sh
log show --info --predicate 'subsystem == "com.inchan.ccmeter"' --last 1m | grep -E "SELF-CHECK|CRED-SRC|REFRESH"
```

정상 시작 시 기대 로그:

```
[com.inchan.ccmeter:app]   CCMeter started (bundleId=<private>)
[com.inchan.ccmeter:usage] [CRED-SRC] keychain
[com.inchan.ccmeter:app]   [SELF-CHECK OK] status bar image size=(133.51, 22.0)
[com.inchan.ccmeter:usage] [REFRESH ok] id=... 5h=NN 7d=NN
```

`SELF-CHECK` 의 image size 가 `(< 10, < 10)` 이면 메뉴바 라벨 가시성 회귀입니다. 자세한 가드 항목은 [ARCHITECTURE.md](ARCHITECTURE.md) D6 참조.

## 라이선스

내부 도구. 외부 배포 시 별도 결정.
