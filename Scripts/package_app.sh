#!/bin/bash

set -euo pipefail

CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="${SCHEME:-DeanConversionTool}"
PROJECT="${PROJECT:-DeanConversionTool.xcodeproj}"
APP_NAME="${APP_NAME:-Dean Conversion Tool}"
BUILD_ROOT="${BUILD_ROOT:-build/package}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_ROOT/DerivedData}"
EXPORT_DIR="$BUILD_ROOT/$CONFIGURATION"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
STAGING_DIR="$EXPORT_DIR/staging"
DMG_PATH="$EXPORT_DIR/$APP_NAME.dmg"
REQUIRED_RESOURCE="$STAGING_DIR/$APP_NAME.app/Contents/Resources/speaker_diarization.py"

SKIP_DEPENDENCY_CHECK=false
SKIP_DMG=false

for arg in "$@"; do
    case "$arg" in
        --skip-dependency-check)
            SKIP_DEPENDENCY_CHECK=true
            ;;
        --skip-dmg)
            SKIP_DMG=true
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: Scripts/package_app.sh [--skip-dependency-check] [--skip-dmg]"
            exit 1
            ;;
    esac
done

cd "$(dirname "$0")/.."

if [[ "$SKIP_DEPENDENCY_CHECK" != true ]]; then
    Scripts/check_dependencies.sh
fi

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
else
    echo "xcodegen is not installed. Install it with: brew install xcodegen"
    exit 1
fi

rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build

if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle was not created: $APP_PATH"
    exit 1
fi

mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

if [[ ! -f "$REQUIRED_RESOURCE" ]]; then
    echo "Required bundled resource is missing: $REQUIRED_RESOURCE"
    exit 1
fi

echo "App bundle:"
echo "  $STAGING_DIR/$APP_NAME.app"

if [[ "$SKIP_DMG" == true ]]; then
    exit 0
fi

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "DMG:"
echo "  $DMG_PATH"
