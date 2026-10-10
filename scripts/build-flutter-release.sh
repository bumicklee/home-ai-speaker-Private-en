#!/bin/bash
# AI-PA app - release build
# Usage: ./scripts/build-flutter-release.sh [android|ios|all] [--no-test] [--no-clean]
#
#   android    Android APK (direct install) + AAB (Play Store)
#   ios        iOS IPA (unsigned; sign in Xcode to distribute)
#   all        both
#   --no-test  skip static analysis and tests before building
#   --no-clean skip flutter clean (faster)
#
# Output: releases/ai-pa-<version>-<date>.{apk,aab,ipa}
# Install on phone: adb install -r releases/ai-pa-….apk

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FLUTTER_DIR="$PROJECT_ROOT/flutter"
OUTPUT_DIR="$PROJECT_ROOT/releases"
APP_NAME="ai-pa"
TARGET="android"
RUN_TESTS=1
CLEAN=1

for arg in "$@"; do
    case $arg in
        android|ios|all) TARGET="$arg" ;;
        --no-test) RUN_TESTS=0 ;;
        --no-clean) CLEAN=0 ;;
        -h|--help)
            sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg (help: $0 --help)"
            exit 1
            ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "AI-PA app - release build (${TARGET})"
echo -e "==========================================${NC}"
echo ""

if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter is not installed.${NC}"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
cd "$FLUTTER_DIR"

echo -e "${CYAN}[1/5] Dependencies and strings...${NC}"
if [ "$CLEAN" -eq 1 ]; then
    flutter clean
fi
flutter pub get
python3 tool/merge_arb.py
flutter gen-l10n

if [ "$RUN_TESTS" -eq 1 ]; then
    echo ""
    echo -e "${CYAN}[2/5] Static analysis and tests...${NC}"
    flutter analyze
    flutter test --reporter compact
else
    echo ""
    echo -e "${YELLOW}[2/5] Skipping analysis and tests (--no-test)${NC}"
fi

VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
DATE=$(date +%Y%m%d_%H%M)
BASE="$OUTPUT_DIR/${APP_NAME}-${VERSION}-${DATE}"
echo ""
echo -e "${GREEN}Version: ${VERSION}${NC}"

build_android() {
    echo ""
    echo -e "${CYAN}[3/5] Android APK build...${NC}"
    flutter build apk --release
    cp build/app/outputs/flutter-apk/app-release.apk "${BASE}.apk"
    echo -e "${GREEN}✓ APK $(du -h "${BASE}.apk" | cut -f1) → ${BASE}.apk${NC}"

    echo ""
    echo -e "${CYAN}[4/5] Android AAB build (for the Play Store)...${NC}"
    flutter build appbundle --release
    cp build/app/outputs/bundle/release/app-release.aab "${BASE}.aab"
    echo -e "${GREEN}✓ AAB $(du -h "${BASE}.aab" | cut -f1) → ${BASE}.aab${NC}"

    if grep -q 'signingConfigs.getByName("debug")' android/app/build.gradle.kts; then
        echo -e "${YELLOW}  ⚠ No release signing key, so it was signed with the debug key. Direct install (adb) on family phones works, but${NC}"
        echo -e "${YELLOW}    to publish to the Play Store, create an upload key and change the signingConfig in build.gradle.kts.${NC}"
    fi
}

build_ios() {
    echo ""
    echo -e "${CYAN}[3/5] iOS IPA build (unsigned)...${NC}"
    if ! command -v xcodebuild &> /dev/null; then
        echo -e "${RED}Error: Xcode is not installed.${NC}"
        return 1
    fi
    flutter build ipa --release --no-codesign
    IPA=$(ls build/ios/ipa/*.ipa 2>/dev/null | head -1 || true)
    if [ -n "$IPA" ]; then
        cp "$IPA" "${BASE}.ipa"
        echo -e "${GREEN}✓ IPA → ${BASE}.ipa${NC}"
    else
        echo -e "${YELLOW}⚠ No IPA file was produced (signing required). Archive: flutter/build/ios/archive/${NC}"
    fi
}

case $TARGET in
    android) build_android ;;
    ios) build_ios ;;
    all)
        build_android
        build_ios
        ;;
esac

echo ""
echo -e "${CYAN}[5/5] Result${NC}"
echo -e "${GREEN}=========================================="
echo "Build complete"
echo -e "==========================================${NC}"
ls -lh "${BASE}".* 2>/dev/null || true
echo ""
echo "Install:"
echo "  Android: adb install -r ${BASE}.apk"
echo "  iOS:     Xcode (Window > Devices and Simulators) or Apple Configurator"
