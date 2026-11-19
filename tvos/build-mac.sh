#!/usr/bin/env bash
#
# Build the Mac app for sharing: dist/Photomosaic.app and dist/Photomosaic-<version>.zip.
#
# Universal (Apple silicon and Intel), macOS 14 or later. Signed ad hoc ("Sign to Run
# Locally"): no Apple ID or developer account involved, and it never expires. On another
# Mac it opens after a one-time "Open Anyway" in System Settings → Privacy & Security.
#
#   tvos/build-mac.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
BUILD="$DIST/build"
VERSION="$(cat "$ROOT/VERSION")"

echo "Building Photomosaic $VERSION for the Mac…"
rm -rf "$DIST/Photomosaic.app" "$DIST"/Photomosaic-*.zip
mkdir -p "$DIST"
if ! xcodebuild -project "$ROOT/tvos/PhotomosaicTV.xcodeproj" -scheme Photomosaic -configuration Release \
     -destination "generic/platform=macOS" -derivedDataPath "$BUILD" ONLY_ACTIVE_ARCH=NO \
     build > "$DIST/build.log" 2>&1; then
  echo "Build failed. Details: $DIST/build.log"
  grep -m5 "error:" "$DIST/build.log" | sed 's/^/    /'
  exit 1
fi

ditto "$BUILD/Build/Products/Release/Photomosaic.app" "$DIST/Photomosaic.app"
codesign --verify --deep "$DIST/Photomosaic.app"
( cd "$DIST" && ditto -c -k --keepParent Photomosaic.app "Photomosaic-$VERSION.zip" )

echo "Architectures: $(lipo -archs "$DIST/Photomosaic.app/Contents/MacOS/Photomosaic")"
echo "Ready to share: $DIST/Photomosaic-$VERSION.zip ($(du -h "$DIST/Photomosaic-$VERSION.zip" | cut -f1))"
echo "App to drag into Applications: $DIST/Photomosaic.app"
