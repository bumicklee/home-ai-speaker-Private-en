#!/bin/bash
# AI-PA app - build and run on a phone
# Usage: ./scripts/run-flutter.sh [android|ios] [--release|--profile]
#
#   android    run on an Android phone
#   ios        run on an iPhone
#   (omitted)  picks the connected phone automatically; asks if both are present
#   --release  release mode (the app keeps running with USB unplugged)
#   --profile  profile mode (performance measurement)
#   default    debug mode (hot reload available, keep USB connected)
#
# The phone and the speaker must be on the same Wi-Fi for the LAN connection after first-time setup.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/.."
FLUTTER_DIR="$PROJECT_ROOT/flutter"
TARGET=""
BUILD_MODE="debug"

for arg in "$@"; do
    case $arg in
        android) TARGET="android" ;;
        ios) TARGET="ios" ;;
        --release|-r) BUILD_MODE="release" ;;
        --profile|-p) BUILD_MODE="profile" ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
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
echo "AI-PA app - run on a phone"
echo -e "==========================================${NC}"
echo ""

if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter is not installed.${NC}"
    exit 1
fi
flutter --version | head -1
echo ""

cd "$FLUTTER_DIR"

echo -e "${CYAN}[1/4] Dependencies and strings...${NC}"
flutter pub get
# Merge the per-feature strings (lib/l10n/parts) and bring the generated files up to date
python3 tool/merge_arb.py
flutter gen-l10n

echo ""
echo -e "${CYAN}[2/4] Checking connected phones...${NC}"
# Pick only real devices from flutter devices --machine (JSON) (no emulators, desktop or web)
DEVICES_JSON=$(flutter devices --machine 2>/dev/null || echo "[]")
read -r ANDROID_ID ANDROID_NAME IOS_ID IOS_NAME <<< "$(python3 - "$DEVICES_JSON" <<'PY'
import json, sys
try:
    devices = json.loads(sys.argv[1])
except ValueError:
    devices = []
def pick(platform_prefix):
    for d in devices:
        if d.get("emulator"):
            continue
        if d.get("targetPlatform", "").startswith(platform_prefix):
            return d["id"], d.get("name", "").replace(" ", "_")
    return "-", "-"
a = pick("android")
i = pick("ios")
print(a[0], a[1], i[0], i[1])
PY
)"

[ "$ANDROID_ID" = "-" ] && ANDROID_ID=""
[ "$IOS_ID" = "-" ] && IOS_ID=""
[ -n "$ANDROID_ID" ] && echo -e "${GREEN}Android: ${ANDROID_NAME//_/ } (${ANDROID_ID})${NC}"
[ -n "$IOS_ID" ] && echo -e "${GREEN}iOS: ${IOS_NAME//_/ } (${IOS_ID})${NC}"

if [ -z "$ANDROID_ID" ] && [ -z "$IOS_ID" ]; then
    echo -e "${RED}Error: no phone is connected.${NC}"
    echo ""
    echo "How to connect:"
    echo "  Android: Developer options > turn on USB debugging → connect USB → tap 'Allow' on the phone"
    echo "  iOS: register and trust the device in Xcode → connect USB (needs the iOS platform in Xcode > Settings > Components)"
    echo ""
    flutter devices
    exit 1
fi

if [ -z "$TARGET" ]; then
    if [ -n "$ANDROID_ID" ] && [ -n "$IOS_ID" ]; then
        echo -e "${YELLOW}Both an Android phone and an iPhone are connected. Choose one:${NC}"
        echo "  1) Android"
        echo "  2) iOS"
        read -r -p "Choice [1-2]: " choice
        case $choice in
            2) TARGET="ios" ;;
            *) TARGET="android" ;;
        esac
    elif [ -n "$ANDROID_ID" ]; then
        TARGET="android"
    else
        TARGET="ios"
    fi
fi

case $TARGET in
    android) DEVICE_ID="$ANDROID_ID" ;;
    ios) DEVICE_ID="$IOS_ID" ;;
esac
if [ -z "$DEVICE_ID" ]; then
    echo -e "${RED}Error: no ${TARGET} device is connected.${NC}"
    exit 1
fi

MODE_FLAG=""
[ "$BUILD_MODE" = "release" ] && MODE_FLAG="--release"
[ "$BUILD_MODE" = "profile" ] && MODE_FLAG="--profile"

echo ""
echo -e "${CYAN}[3/4] Build mode: ${BUILD_MODE}${NC}"
if [ "$BUILD_MODE" = "release" ] && [ "$TARGET" = "android" ]; then
    echo -e "${YELLOW}  Note: there is no release signing key yet, so it is signed with the debug key (android/app/build.gradle.kts).${NC}"
fi

echo ""
echo -e "${CYAN}[4/4] Running the app (${TARGET}: ${DEVICE_ID})...${NC}"
echo ""
echo "  Hot reload: r   Hot restart: R   Quit: q"
echo ""
flutter run -d "$DEVICE_ID" $MODE_FLAG
