---
name: ship-claude-code-menubar
description: Claude Code Menubar 프로젝트의 출하 파이프라인. 사용자가 "/ship-claude-code-menubar", "출시", "릴리즈 해줘", "정리하고 배포", "메뉴바 앱 배포", "ship it" 같은 표현으로 정리→문서→빌드/로컬 배포→커밋·푸시·PR 전체 흐름을 요청할 때 자동 로드한다. 단계별로 사용자 승인을 받으며 진행하고, 절대 사용자 승인 없이 destructive 동작(파일 삭제, push, PR 생성, self-merge)을 수행하지 않는다.
---

# /ship-claude-code-menubar — Claude Code Menubar 출하 파이프라인

이 스킬은 Claude Code Menubar 프로젝트(`~/workspace/inchan/claude-code-menubar`)에 한정한 출하 절차를 안내한다.
브랜치 정책은 **`develop` 이 작업 브랜치**이며 **`main` 푸시는 PR 을 통해서만** 일어난다.
`main` 으로 머지되면 GitHub Actions(`.github/workflows/release.yml`)가 자동으로 패치 버전 릴리즈를 만든다.

## 프로젝트 컨텍스트 (단일 정의원)

- **빌드 시스템**: Swift Package Manager (`swift build` / `swift test`) + `Makefile` 로 .app 번들 조립
- **메뉴바 앱**: `LSUIElement=true` (Dock 없음), 단일 인스턴스 (`Paths.appInstanceLockFile`)
- **패키징**: `make app` — swift release 빌드 + `AppIcon.icns` 생성(rsvg-convert + iconutil) + `Info.plist` + codesign
- **서명**: `Apple Development: inchan kang (3U27437JKX)` — 안정 designated requirement 로 Keychain ACL 재등록 회피
- **로컬 배포**: `make install` → `~/Applications/ClaudeCodeMenubar.app`
- **자동 시작**: SMAppService BTM 등록 — `App.swift` 의 `LaunchAtLoginService.reconcileAtLaunch` 가 시작 시 재등록
- **테스트**: 155개 단위/통합 테스트 (커버리지 ~91%)
- **CI**: `.github/workflows/release.yml` — main push 시 자동 패치 릴리즈

## 실행 원칙

- **4단계 순차**: 정리 → 문서 → 빌드/로컬 배포 → 커밋·푸시·PR
- **각 단계 시작 전 사용자 확인** (변경 범위 보고 + Y/N)
- **destructive 동작은 사용자 명시 승인 후에만**:
  - 파일 삭제, `git push`, `gh pr create`, `gh pr merge`, `git reset --hard` 등
- 단계 도중 실패하면 다음 단계로 넘어가지 않고 보고 후 사용자 판단을 기다린다
- 브랜치는 항상 `develop` 위에서만 작업한다. `main` 직접 푸시 금지

## 사전 점검 (Stage 0)

다음을 병렬로 수집하고 보고한다:

```bash
git status --short
git rev-parse --abbrev-ref HEAD
git log --oneline origin/main..HEAD
git log --oneline origin/develop..HEAD 2>/dev/null
gh auth status 2>&1 | head -8
make show-cert
```

### 점검 항목

- **현재 브랜치**: `develop` 이 아니면 사용자에게 전환 여부 질문 (`git switch develop`). 워킹트리 dirty 면 stash 또는 commit 선결
- **gh 활성 계정**: `inchan` 이 아니면 이전 계정명을 변수에 저장 후 `gh auth switch -u inchan`. **Stage 4 종료 시 반드시 이전 계정으로 복원**
- **git config user.email**: `kangsazang@gmail.com` 이 아니면 로컬 설정 (사용자 확인 후)
- **codesign identity**: `Apple Development: inchan kang` 가용 여부. 없으면 `make setup-cert` 안내 후 중단
- **rsvg-convert** (아이콘 빌드 의존성) 존재 확인. 없으면 `brew install librsvg` 안내

## Stage 1 — 정리

### 스캔 항목

병렬로 수행하고 결과를 군대식 보고서로 요약한다.

```bash
# TODO/FIXME/HACK + 옛 이름 잔재
grep -rn "TODO\|FIXME\|XXX\|HACK" Sources Tests 2>/dev/null
grep -rn "cc-account-manager\|CCAccountManager" Sources Tests 2>/dev/null

# Swift 미사용 import / 의심 죽은 코드
grep -rn "^import " Sources 2>/dev/null | sort -u

# 빌드 산출물·캐시·임시파일
ls -la .build/ build/ 2>/dev/null
find . -name '*.bak.*' -not -path './.build/*' -not -path './.git/*' 2>/dev/null
find . -name '.DS_Store' 2>/dev/null

# 워크트리 잔재 (.claude/worktrees/*) — 머지 완료된 브랜치 정리 후보
git worktree list

# docs/ 내 미사용 산출물
ls docs/ docs/screenshots/ 2>/dev/null
```

### 정리 정책

- **빌드 산출물**(`build/`, `.build/`): `.gitignore` 대상이면 그대로. 추적 중이면 사용자에게 제거 제안
- **`.bak.*`**: 사용자 환경 백업은 건드리지 않음. 레포 내부만 후보로 보고
- **`.DS_Store`**: 발견 시 일괄 제거 후보로 보고 (사용자 승인 필수)
- **워크트리**: `.claude/worktrees/*` 중 본 사이클에서 main 으로 머지된 브랜치의 워크트리는 정리 후보로 보고. **자동 삭제 금지** — 미커밋 변경 있을 수 있음
- **죽은 코드**:
  - Swift `private` 심볼인데 참조 0개 → 후보 보고
  - 미사용 `import` → grep 으로 의심 후보 보고
  - 빈 함수, `_ = ` 의미 없는 무시 패턴 보고
- **주석 정리**:
  - 코드와 어긋난 한글 주석, 자기설명적 주석, 옛 이름(`cc-account-manager` 등) 잔재 보고
  - **WHY 가 적힌 주석은 보존** (예: `// Keychain 만 갱신하고 파일은 stale 로 남는 동작 회피` 같은 회귀 방지 주석)
- **테스트 자산**: `Tests/ClaudeCodeMenubarTests/` 내 미사용 fixture/임시 파일 후보 보고

### 출력 형식

```
## Stage 1 정리 후보

[자동 삭제 가능]
- <path> — <이유>

[사용자 확인 필요]
- <path> — <이유>

[보존]
- <path> — <이유>
```

사용자에게 `AskUserQuestion` 으로 삭제 범위 확정한 뒤 실행한다.

## Stage 2 — 문서 업데이트

### 점검 대상

- `README.md` — 최신 기능(메뉴바 popover, 계정 전환, Keychain 권한 거부 처리, 자동 시작) 반영 여부
- `ARCHITECTURE.md` — 새 모듈(`LaunchAtLoginService`, `ClaudeKeychainCredentials.readDetailed`, `StatusIconRenderer.drawWarningBadge` 등) 추가 반영 여부
- `docs/icon-concepts.html` — 시안 비교 페이지가 최신 적용 아이콘과 일치하는지
- `docs/screenshots/` — popover/메뉴바 스크린샷이 최신 디자인인지
- `Resources/Info.plist.template` — `CFBundleShortVersionString` 이 의도한 버전인지 (CI 가 자동으로 패치 증가시키므로 main 머지 후 자동 갱신)

### 작업 정책

- 발견된 누락만 보고하고, **추가/수정 패치를 보여준 뒤 적용 여부를 사용자에게 묻는다**
- 새 스크린샷이 필요해 보이면 캡처 명령(`screencapture -i`) 제안만 — 자동 캡처 금지
- 문서 톤은 기존 한국어 톤 + 군대식 요약 유지
- `README.md` 의 popover 스크린샷·demo gif 가 redesign 반영 안 됐으면 후보로 보고 (자동 갱신은 사용자 승인 후)

## Stage 3 — 빌드 / 로컬 배포

### 3-1 테스트

```bash
swift test 2>&1 | tail -5
```

- 155개 테스트 전수 통과 확인. 실패 시 즉시 중단하고 에러 보고

### 3-2 빌드 + 로컬 설치 (한 번에)

`make install` 은 `install: app` 의존성으로 release 빌드를 내부 호출하므로 별도 `make app` 호출 불필요 (중복 빌드 방지).

```bash
# 기존 프로세스 종료 (메뉴바 앱 단일 인스턴스 락 회피)
pkill -f "$HOME/Applications/ClaudeCodeMenubar.app/Contents/MacOS/ClaudeCodeMenubar" 2>/dev/null
sleep 1

# 깨끗한 빌드 후 설치 (앱 빌드 + 아이콘 + codesign + ~/Applications 복사 전부 수행)
make clean && make install 2>&1 | tail -20

# LaunchServices 캐시 갱신 — 아이콘/Info.plist 변경 즉시 반영
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f ~/Applications/ClaudeCodeMenubar.app

# 실행 + 검증
open ~/Applications/ClaudeCodeMenubar.app
sleep 2
pgrep -fl ClaudeCodeMenubar | head -3
launchctl list | grep -i claude-code-menubar || echo "(BTM 미등록 — 첫 실행 시 reconcileAtLaunch 가 등록함)"
plutil -extract CFBundleIconFile raw ~/Applications/ClaudeCodeMenubar.app/Contents/Info.plist
ls ~/Applications/ClaudeCodeMenubar.app/Contents/Resources/AppIcon.icns
```

**서명 검증 (로컬 빌드 한정)**

- `make install` 로그에 `>> codesign with stable identity: Apple Development: inchan kang` 출력 확인
- 아이콘 빌드 흔적 확인 (`>> iconutil → .../AppIcon.icns`)
- ad-hoc 서명으로 떨어지면 (`>> codesign ad-hoc`) 즉시 중단 + `make setup-cert` 안내 — 사용자 Keychain 권한 팝업이 매 빌드마다 뜨는 회귀
- **CI (`release.yml`) 는 ad-hoc 서명이 정상** — GitHub Actions runner 에 `Apple Development` 인증서가 없으므로 의도적. 안정 서명 게이트는 로컬 빌드에만 적용한다

### 3-3 동작 점검 (사용자 시각 확인)

사용자에게 다음을 직접 확인 요청:

1. 메뉴바에 Claude Code Menubar 아이콘 노출 — 이니셜 원형 + 사용량 표시
2. 클릭 → popover 의 계정 카드 정상 렌더링 (settings-redesign 적용본)
3. ⌘, → 설정 창 — 사이드바 + 패널 정상 표시
4. ⌘R → 새로고침 동작
5. Finder/Dock 아이콘 = B·10 시안 (`killall Finder Dock` 필요 시 안내)

빌드 실패 또는 시각 점검에서 회귀 발견 시 즉시 중단하고 사용자 판단 대기.

## Stage 4 — 커밋 · 푸시 · PR

### 4-1 커밋 (이미 작업 중 커밋했다면 skip)

```bash
git status --short
git diff --stat
git log --oneline -5
```

- 변경 단위로 커밋 메시지 초안 작성 (Conventional Commits 권장: `feat`, `fix`, `chore`, `docs`, `refactor`, `ci`)
- 한국어 커밋 메시지를 기존 컨벤션으로 유지 (최근 커밋 로그 패턴 따른다)
- **메시지에 Claude Code 서명을 임의로 추가하지 않는다** — 최근 커밋(`b408348`, `f480364`, `58fd733`) 어디에도 Co-Authored-By 서명 없음
- 사용자 승인 후 커밋:

```bash
git add <specific files>   # NEVER use `git add -A`
git commit -m "$(cat <<'EOF'
<type>: <title>

<body>
EOF
)"
```

### 4-2 푸시 — 사용자 명시 승인 후

```bash
git push origin develop
```

### 4-2.5 develop ← main 동기화 (PR 충돌 사전 차단)

squash 머지를 반복하면 main 의 squash 커밋 SHA 가 develop 에 없어 PR 생성 후 충돌(`mergeStateStatus=DIRTY`) 이 자주 난다. PR 만들기 직전에 main 을 develop 에 머지해 충돌을 미리 흡수한다.

```bash
git fetch origin main
git merge origin/main --no-edit
```

- 충돌 발생 시 일반적으로 develop 본(ours) 채택. 이번 사이클 변경은 모두 develop 최신본에 있고 main 은 직전 squash 결과라 ours 가 진실에 가깝다. 단, **사용자가 main 에 직접 패치를 적용한 흔적이 있으면 그 부분만 손으로 검토**
- 충돌 해결 후 머지 커밋: `git commit --no-edit`
- merge 커밋 푸시: `git push origin develop`
- fast-forward 가능하면 그대로 통과 — 그 경우도 push 한 번 더 해두면 안전

### 4-3 PR develop → main

PR 본문은 변경 요약 + 시각 검증 체크리스트 형식.

```bash
gh pr create --base main --head develop --title "<title>" --body "$(cat <<'EOF'
## Summary
- <1-3 bullet>

## Changes
- <area> — <what>

## Test plan
- [ ] swift test 155개 통과
- [ ] make install 후 메뉴바 아이콘 정상 동작
- [ ] 계정 전환 / popover / 설정창 회귀 없음
- [ ] Keychain 권한 거부 시 ! 배지 + 새로고침 동작
- [ ] LaunchAtLogin reconciliation 동작 확인 (launchctl list | grep claude-code-menubar)
- [ ] Finder/Dock 아이콘 = B·10 시안

EOF
)"
```

- PR URL 을 사용자에게 출력
- main 보호 규칙 확인: `gh api repos/inchan/claude-code-menubar/branches/main/protection 2>/dev/null` — `required_approving_review_count` 가 0 이면 작성자(`inchan`) 가 직접 `gh pr merge <N> --squash --delete-branch=false` 로 머지 가능. **사용자에게 self-merge 진행 여부를 묻고 승인 시에만 수행**
- 머지 후 CI `release.yml` 이 자동으로 패치 버전 릴리즈 생성

### 4-4 계정 복원 (필수 — 최우선)

Stage 0 에서 `inchan` 외 다른 계정에서 전환했다면 후속 안내 전에 **즉시 복원**한다. 복원 누락 시 사용자의 다른 작업이 잘못된 계정으로 진행될 위험 있음.

```bash
gh auth switch -u <previous-account>
```

### 4-5 후속 안내

```
다음 단계:
1. PR 리뷰 후 main 머지 (self-merge 한 경우 skip)
2. GitHub Actions release.yml 진행 상태 확인: gh run list --workflow=release.yml --limit 3
3. gh release view --web 로 새 릴리즈 확인
4. 필요 시 릴리즈 노트에 본 사이클 주요 변경 수동 보강
```

## 금지 사항

- 사용자 미확인 상태 파일 삭제
- `git push --force`, `git reset --hard` (사용자가 명시 요청한 경우 제외)
- `main` 직접 푸시
- `--no-verify`, `--no-gpg-sign` 같은 훅/서명 우회
- `.env`, 키, 자격증명 파일 커밋 (Claude OAuth credentials JSON 포함)
- PR 자동 머지 (사용자 명시 승인 없이)
- ad-hoc 서명으로 release 빌드 진행 (Keychain ACL 회귀 유발)
- 메뉴바 앱 실행 중 install 강행 (단일 인스턴스 락 충돌)
- `git worktree remove --force` (미커밋 디자인 작업 손실 위험)

## 부분 실행

사용자가 특정 단계만 원하면 그 단계만 수행한다:
- `/ship-claude-code-menubar cleanup` → Stage 1 만
- `/ship-claude-code-menubar docs` → Stage 2 만
- `/ship-claude-code-menubar build` → Stage 3 만 (테스트 + 빌드 + 로컬 설치)
- `/ship-claude-code-menubar release` → Stage 4 만 (커밋·푸시·PR)

## Claude Code Menubar 특화 회귀 회피 체크리스트

본 프로젝트에서 과거에 발생한 회귀를 차단하기 위한 자동 점검:

1. **Keychain 토큰 stale fallback** — `UsageMonitor.refresh()` 에서 활성 계정 Keychain 권한 거부 시 stale 파일 fallback 차단 확인 (`keychain_denied` 에러 분기 존재 여부 grep)
2. **단일 인스턴스 락** — `App.swift` 의 `enforceSingleInstance()` 호출 유지 확인
3. **안정 서명 (로컬 빌드 한정)** — `make app` 결과에서 `Apple Development:` 로그 확인. ad-hoc 발견 시 즉시 중단. CI (`release.yml`) 는 ad-hoc 정상 — runner 에 인증서 없음
4. **아이콘 빌드 의존성** — `rsvg-convert` 가용 여부 사전 체크
5. **`LSUIElement=true`** — Info.plist.template 에서 키 보존 확인 (메뉴바 전용 앱 회귀)
6. **테스트 커버리지** — 155개 이하로 떨어지면 회귀 의심
