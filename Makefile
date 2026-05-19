SHELL := /bin/bash
APP_NAME := ClaudeCodeMenubar
DISPLAY_NAME := Claude Code Menubar
BUILD_CONFIG := release
BIN_PATH := .build/$(BUILD_CONFIG)/$(APP_NAME)
APP_BUNDLE := build/$(DISPLAY_NAME).app
INSTALL_DIR := $(HOME)/Applications

# Stable Code Signing identity 자동 감지.
# 1. SIGN_NAME 환경변수 명시 시 그 이름과 매칭되는 cert
# 2. 없으면 Keychain 의 첫 codesigning identity 자동 사용 (Apple Development 등)
# 3. 둘 다 없으면 ad-hoc (`make setup-cert` 로 self-signed 생성 가능)
SIGN_NAME ?=
SIGN_IDENTITY := $(shell bash scripts/detect-cert.sh "$(SIGN_NAME)")

.PHONY: all build app install run clean test fmt setup-cert show-cert icon

all: app

build:
	swift build -c $(BUILD_CONFIG)

icon:
	@bash scripts/build-icon.sh

app: build icon
	@echo ">> Assembling .app bundle"
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp "$(BIN_PATH)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Resources/Info.plist.template "$(APP_BUNDLE)/Contents/Info.plist"
	@cp build/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@if [ -d "$(BIN_PATH)_CCMeter.bundle" ]; then \
		cp -R "$(BIN_PATH)_CCMeter.bundle/." "$(APP_BUNDLE)/Contents/Resources/"; \
	fi
	@if [ -n "$(SIGN_IDENTITY)" ]; then \
		echo ">> codesign with stable identity: $(SIGN_IDENTITY)"; \
		codesign --force --deep --sign "$(SIGN_IDENTITY)" "$(APP_BUNDLE)"; \
	else \
		echo ">> codesign ad-hoc (Keychain prompts every build)"; \
		echo ">> 안정 서명을 원하면: make setup-cert"; \
		codesign --force --deep --sign - "$(APP_BUNDLE)"; \
	fi
	@echo ">> Built: $(APP_BUNDLE)"

install: app
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(INSTALL_DIR)/$(DISPLAY_NAME).app"
	@cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	@echo ">> Installed to $(INSTALL_DIR)/$(DISPLAY_NAME).app"

run: app
	@open "$(APP_BUNDLE)"

test:
	swift test

clean:
	rm -rf .build build

fmt:
	@command -v swift-format >/dev/null 2>&1 && swift-format -i -r Sources Tests || echo "swift-format not installed; skipping"

setup-cert:
	@SIGN_NAME="$(SIGN_NAME)" bash scripts/setup-cert.sh

show-cert:
	@security find-identity -v -p codesigning | grep "$(SIGN_NAME)" || \
		echo "  (인증서 없음 — 'make setup-cert' 실행)"
