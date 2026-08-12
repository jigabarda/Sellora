# Sellora Mobile developer commands.
#
# Usage examples:
#   make help
#   make run
#   make run DEVICE=emulator-5554
#   make fresh-run
#   make run-staging
#   make run-build-apk
#   make release
#
# Environment notes:
# - The app does not currently define Android flavors.
# - local/staging/prod are passed through APP_ENV so Flutter code can later read:
#   const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'local');

FLUTTER ?= flutter
DART ?= dart
ADB ?= C:/Users/Andrei/AppData/Local/Android/Sdk/platform-tools/adb.exe
DEVICE_FLAGS := $(if $(DEVICE),-d $(DEVICE),)
ANDROID_PACKAGE ?= com.example.sellora_mobile

LOCAL_DEFINES := --dart-define=APP_ENV=local
STAGING_DEFINES := --dart-define=APP_ENV=staging
PROD_DEFINES := --dart-define=APP_ENV=prod

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Sellora Mobile Makefile"
	@echo ""
	@echo "Daily development:"
	@echo "  make pub-get          Install Flutter dependencies"
	@echo "  make run              Run local/dev app on the selected/default device"
	@echo "  make fresh-run        Clean, fetch deps, then run local/dev"
	@echo "  make run-staging      Run staging environment"
	@echo "  make fresh-run-staging Clean, fetch deps, then run staging"
	@echo "  make run-prod         Run prod environment in release mode"
	@echo "  make analyze          Run Flutter analyzer"
	@echo "  make format           Format all Dart files"
	@echo "  make test             Run Flutter tests"
	@echo "  make verify           Format-check, analyze, then test"
	@echo ""
	@echo "Builds:"
	@echo "  make build            Build local debug APK"
	@echo "  make run-build-apk    Clean, fetch deps, analyze, then build debug APK"
	@echo "  make install-debug    Build and install debug APK on selected/default device"
	@echo "  make fresh-install-debug Clean, fetch deps, build, then install debug APK"
	@echo "  make launch-android   Launch installed Android app with adb"
	@echo "  make fresh-install-launch Clean, build, install, then launch Android app"
	@echo "  make build-apk-local  Build debug APK with APP_ENV=local"
	@echo "  make build-apk-staging Build profile APK with APP_ENV=staging"
	@echo "  make build-apk-prod   Build release APK with APP_ENV=prod"
	@echo "  make build-aab-prod   Build release Android App Bundle with APP_ENV=prod"
	@echo "  make release          Verify, then build production APK and AAB"
	@echo ""
	@echo "Maintenance:"
	@echo "  make doctor           Run flutter doctor"
	@echo "  make devices          List connected devices"
	@echo "  make outdated         Show outdated packages"
	@echo "  make clean            Run flutter clean"
	@echo "  make reset            Clean and reinstall dependencies"
	@echo ""
	@echo "Optional:"
	@echo "  make run DEVICE=emulator-5554"

.PHONY: doctor devices pub-get pub-upgrade outdated
doctor:
	$(FLUTTER) doctor -v

devices:
	$(FLUTTER) devices

pub-get:
	$(FLUTTER) pub get

pub-upgrade:
	$(FLUTTER) pub upgrade

outdated:
	$(FLUTTER) pub outdated

.PHONY: format format-check analyze test verify
format:
	$(DART) format .

format-check:
	$(DART) format --output=none --set-exit-if-changed .

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test

verify: format-check analyze test

.PHONY: clean reset
clean:
	$(FLUTTER) clean

reset: clean pub-get

.PHONY: run run-local run-staging run-prod fresh-run fresh-run-staging fresh-run-prod
run: run-local

run-local:
	$(FLUTTER) run $(DEVICE_FLAGS) $(LOCAL_DEFINES)

run-staging:
	$(FLUTTER) run $(DEVICE_FLAGS) $(STAGING_DEFINES)

run-prod:
	$(FLUTTER) run $(DEVICE_FLAGS) --release $(PROD_DEFINES)

fresh-run: clean pub-get run-local

fresh-run-staging: clean pub-get run-staging

fresh-run-prod: clean pub-get run-prod

.PHONY: build run-build-apk build-apk-debug build-apk-local build-apk-staging build-apk-prod build-aab-prod install-debug fresh-install-debug launch-android fresh-install-launch release
build: build-apk-local

run-build-apk: clean pub-get analyze build-apk-debug

build-apk-debug:
	$(FLUTTER) build apk --debug $(LOCAL_DEFINES)

build-apk-local:
	$(FLUTTER) build apk --debug $(LOCAL_DEFINES)

build-apk-staging:
	$(FLUTTER) build apk --profile $(STAGING_DEFINES)

build-apk-prod:
	$(FLUTTER) build apk --release $(PROD_DEFINES)

build-aab-prod:
	$(FLUTTER) build appbundle --release $(PROD_DEFINES)

install-debug: build-apk-debug
	$(FLUTTER) install --debug $(DEVICE_FLAGS)

fresh-install-debug: clean pub-get build-apk-debug
	$(FLUTTER) install --debug $(DEVICE_FLAGS)

launch-android:
	$(ADB) shell monkey -p $(ANDROID_PACKAGE) -c android.intent.category.LAUNCHER 1

fresh-install-launch: fresh-install-debug launch-android

release: verify build-apk-prod build-aab-prod
