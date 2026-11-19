#!/usr/bin/env bash
#
# Build the Mac app for sharing: dist/Photomosaic.app and dist/Photomosaic-<version>.zip.
# The build itself happens in a temporary folder that's deleted afterwards, so dist holds
# only those two (plus build.log when a build fails).
#
# Universal (Apple silicon and Intel), macOS 14 or later. Signed ad hoc ("Sign to Run
# Locally"): no Apple ID or developer account involved, and it never expires. On another
# Mac it opens after a one-time "Open Anyway" in System Settings → Privacy & Security.
#
#   tvos/build-mac.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
VERSION="$(cat "$ROOT/VERSION")"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/photomosaic-build.XXXXXX")"
APP_BUILT="$BUILD/Build/Products/Release/Photomosaic.app"
cleanup() {
  # Forget the temporary copy (macOS registers built apps), then delete the build folder.
  [ -d "$APP_BUILT" ] && "$LSREGISTER" -u "$APP_BUILT" 2>/dev/null
  rm -rf "$BUILD"
}
trap cleanup EXIT

echo "Building Photomosaic $VERSION for the Mac…"
rm -rf "$DIST/Photomosaic.app" "$DIST"/Photomosaic-*.zip "$DIST/build" "$DIST/build.log"
mkdir -p "$DIST"
if ! xcodebuild -project "$ROOT/tvos/PhotomosaicTV.xcodeproj" -scheme Photomosaic -configuration Release \
     -destination "generic/platform=macOS" -derivedDataPath "$BUILD" ONLY_ACTIVE_ARCH=NO \
     build > "$BUILD/build.log" 2>&1; then
  cp "$BUILD/build.log" "$DIST/build.log"
  echo "Build failed. Details: $DIST/build.log"
  grep -m5 "error:" "$DIST/build.log" | sed 's/^/    /'
  exit 1
fi

ditto "$APP_BUILT" "$DIST/Photomosaic.app"
codesign --verify --deep "$DIST/Photomosaic.app"
( cd "$DIST" && ditto -c -k --keepParent Photomosaic.app "Photomosaic-$VERSION.zip" )

echo "Architectures: $(lipo -archs "$DIST/Photomosaic.app/Contents/MacOS/Photomosaic")"
echo "Ready to share: $DIST/Photomosaic-$VERSION.zip ($(du -h "$DIST/Photomosaic-$VERSION.zip" | cut -f1))"
echo "App to drag into Applications: $DIST/Photomosaic.app"
