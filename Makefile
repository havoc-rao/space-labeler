.PHONY: build test install install-login clean

SHELL := /bin/bash

PROJECT := SpaceLabeler.xcodeproj
SCHEME := SpaceLabeler
LABEL := com.jeremywatt.SpaceLabeler
APP_NAME := SpaceLabeler.app
BUILD_DIR := build

# Versioning: the VERSION file is the single source of truth for the
# marketing version; the build number is the git commit count, so every
# commit produces a distinguishable build. Both are injected as xcodebuild
# overrides (Info.plist resolves them via $(MARKETING_VERSION) /
# $(CURRENT_PROJECT_VERSION)).
MARKETING_VERSION := $(shell cat VERSION 2>/dev/null || echo 0.0.0)
CURRENT_PROJECT_VERSION := $(shell git rev-list --count HEAD 2>/dev/null || echo 0)
VERSION_SETTINGS := MARKETING_VERSION=$(MARKETING_VERSION) CURRENT_PROJECT_VERSION=$(CURRENT_PROJECT_VERSION)

build:
	xcodegen generate
	xcodebuild build \
	  -project $(PROJECT) -scheme $(SCHEME) \
	  -configuration Release -destination 'platform=macOS' \
	  -derivedDataPath $(BUILD_DIR) \
	  $(VERSION_SETTINGS)

test:
	xcodegen generate
	xcodebuild test \
	  -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=macOS' \
	  -derivedDataPath $(BUILD_DIR) \
	  $(VERSION_SETTINGS)

install: build
	mkdir -p $(HOME)/Applications
	# Quit any running instance first: overwriting a live bundle invalidates
	# the Accessibility (TCC) grant for the old binary and can confuse it.
	-pkill -x SpaceLabeler 2>/dev/null
	rm -rf $(HOME)/Applications/$(APP_NAME)
	cp -R $(BUILD_DIR)/Build/Products/Release/$(APP_NAME) $(HOME)/Applications/
	# No TCC surgery here anymore: ad-hoc resigning changes the code
	# fingerprint on every build, so the previous Accessibility grant no
	# longer applies. Mark the next launch to re-request it — the app pops
	# the system authorization dialog itself. Record cleanup also lives in
	# the app: in-app updates clear stale records automatically before
	# swapping in a new build, or via Preferences -> STATUS -> "Clean stale
	# Accessibility records" (sudo prompt handled by the system).
	@defaults write $(LABEL) relaunch.pendingAccessibilityReGrant -bool YES
	@echo "On next launch, the app will ask you to re-grant the Accessibility permission."
	@if [ -f "$(HOME)/Library/LaunchAgents/$(LABEL).plist" ]; then \
	  echo "LaunchAgent detected — restarting managed instance"; \
	  launchctl kickstart -k "gui/$$(id -u)/$(LABEL)"; \
	else \
	  open $(HOME)/Applications/$(APP_NAME); \
	fi

install-login:
	./scripts/install-login-item.sh

clean:
	rm -rf $(PROJECT) $(BUILD_DIR)
