#!/bin/bash

set -euo pipefail

CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="${SCHEME:-DeanConversionTool}"
PROJECT="${PROJECT:-DeanConversionTool.xcodeproj}"
APP_NAME="${APP_NAME:-Dean Conversion Tool}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.dean.conversiontool}"
BUILD_ROOT="${BUILD_ROOT:-build/package}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_ROOT/DerivedData}"
EXPORT_DIR="$BUILD_ROOT/$CONFIGURATION"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
STAGING_DIR="$EXPORT_DIR/staging"
DMG_PATH="$EXPORT_DIR/$APP_NAME.dmg"
REQUIRED_RESOURCE="$STAGING_DIR/$APP_NAME.app/Contents/Resources/speaker_diarization.py"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-}"

SKIP_DEPENDENCY_CHECK=false
SKIP_DMG=false
NOTARIZE=false

for arg in "$@"; do
    case "$arg" in
        --skip-dependency-check)
            SKIP_DEPENDENCY_CHECK=true
            ;;
        --skip-dmg)
            SKIP_DMG=true
            ;;
        --notarize)
            NOTARIZE=true
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: Scripts/package_app.sh [--skip-dependency-check] [--skip-dmg] [--notarize]"
            exit 1
            ;;
    esac
done

cd "$(dirname "$0")/.."

if [[ -f Scripts/release_config.env ]]; then
    # shellcheck disable=SC1091
    source Scripts/release_config.env
fi

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

BUILD_SETTINGS=(
    PRODUCT_BUNDLE_IDENTIFIER="$APP_BUNDLE_ID"
)

if [[ -n "$DEVELOPER_ID_APPLICATION" ]]; then
    if [[ -z "$APPLE_TEAM_ID" ]]; then
        echo "APPLE_TEAM_ID is required when DEVELOPER_ID_APPLICATION is set."
        exit 1
    fi

    BUILD_SETTINGS+=(
        CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
        CODE_SIGN_STYLE=Manual
        CODE_SIGNING_ALLOWED=YES
        CODE_SIGNING_REQUIRED=YES
        DEVELOPMENT_TEAM="$APPLE_TEAM_ID"
        ENABLE_HARDENED_RUNTIME=YES
    )
else
    BUILD_SETTINGS+=(
        CODE_SIGN_IDENTITY=
        CODE_SIGN_STYLE=Manual
        CODE_SIGNING_ALLOWED=NO
        CODE_SIGNING_REQUIRED=NO
        ENABLE_HARDENED_RUNTIME=NO
    )
fi

xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    "${BUILD_SETTINGS[@]}" \
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

if [[ -n "$DEVELOPER_ID_APPLICATION" ]]; then
    codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/$APP_NAME.app"
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

if [[ -n "$DEVELOPER_ID_APPLICATION" ]]; then
    codesign --force --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ "$NOTARIZE" == true ]]; then
    if [[ -z "$NOTARYTOOL_PROFILE" ]]; then
        echo "NOTARYTOOL_PROFILE is required when --notarize is used."
        echo "Create one with: xcrun notarytool store-credentials <profile-name>"
        exit 1
    fi
    if [[ -z "$DEVELOPER_ID_APPLICATION" ]]; then
        echo "DEVELOPER_ID_APPLICATION is required when --notarize is used."
        exit 1
    fi

    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

echo "DMG:"
echo "  $DMG_PATH"
