#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Wenku8Studio"
APP_BUNDLE="$ROOT_DIR/$APP_NAME.app"
DERIVED_DIR="$SCRIPT_DIR/.build_xcode"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "Generating Xcode project via xcodegen..."
cd "$SCRIPT_DIR"
xcodegen generate

echo "Building $APP_NAME with Xcode (Liquid Glass + Asset Catalog AppIcon)..."
xcodebuild \
  -project "$SCRIPT_DIR/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -sdk macosx \
  -derivedDataPath "$DERIVED_DIR" \
  build

BUILT_APP="$DERIVED_DIR/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Error: built app not found at $BUILT_APP"
  exit 1
fi

rm -rf "$APP_BUNDLE"
ditto "$BUILT_APP" "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

# Prevent LaunchServices icon flicker caused by duplicate bundle paths (.build_xcode vs root .app)
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$BUILT_APP" >/dev/null 2>&1 || true
  "$LSREGISTER" -f -R -trusted "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "Built $APP_BUNDLE successfully with Xcode!"
