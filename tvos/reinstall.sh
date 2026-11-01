#!/bin/bash
# Renew and reinstall Photomosaic on the Apple TV.
#
# Free Apple ID installs expire after 7 days, and a plain reinstall reuses the old
# provisioning profile, so this script sets that profile aside, lets Xcode fetch a fresh
# 7-day one, rebuilds, and installs.
#
# It builds the latest code pushed to GitHub, from its own copy in ~/Library/Caches
# (background jobs can't read ~/Documents). The scheduled copy of this script lives in
# ~/Library/Application Support/Photomosaic/ and runs from
#   ~/Library/LaunchAgents/com.marioalonso.photomosaic.reinstall.plist
#   (Mondays and Thursdays at 04:00; a missed run happens when the Mac wakes).
# After editing this script, copy it there again.
#
# Log: ~/Library/Logs/Photomosaic-reinstall.log
#
# Needs: the Mac on the same network as the Apple TV (the TV may be asleep), and Xcode
# signed in to the Apple ID (Xcode → Settings → Apple Accounts).
#
# To remove the schedule:
#   launchctl bootout gui/$(id -u)/com.marioalonso.photomosaic.reinstall
#   rm ~/Library/LaunchAgents/com.marioalonso.photomosaic.reinstall.plist
#   rm -r ~/Library/Application\ Support/Photomosaic ~/Library/Caches/PhotomosaicTV-build

set -uo pipefail

DEVICE="00008110-0004299A3A05801E"   # Apple TV "Sala" (xcrun devicectl list devices)
BUNDLE="com.marioalonso.PhotomosaicTV"
REPO="https://github.com/MarAlons0/photomosaic.git"
WORK="$HOME/Library/Caches/PhotomosaicTV-build"
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
APP="$WORK/dd/Build/Products/Release-appletvos/PhotomosaicTV.app"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S')  $*"; }
mkdir -p "$WORK/old-profiles"

# 1. The Apple TV must be reachable; otherwise leave everything as it is.
if ! xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -qE "available|connected"; then
  log "Apple TV not reachable (Mac away from home, or TV off the network). Nothing changed."
  exit 1
fi

# 2. Get the latest released code.
if [ -d "$WORK/src/.git" ]; then
  git -C "$WORK/src" pull --quiet --ff-only || { log "Couldn't update the code from GitHub."; exit 1; }
else
  git clone --quiet "$REPO" "$WORK/src" || { log "Couldn't download the code from GitHub."; exit 1; }
fi

# 3. Set aside this app's current profile so Xcode fetches a fresh 7-day one.
moved=()
for f in "$PROFILES"/*.mobileprovision; do
  [ -e "$f" ] || continue
  name=$(security cms -D -i "$f" 2>/dev/null | plutil -extract Name raw -o - - 2>/dev/null)
  if [[ "$name" == *PhotomosaicTV* ]]; then
    mv "$f" "$WORK/old-profiles/" && moved+=("$(basename "$f")")
  fi
done

# 4. Rebuild (signing fetches the new profile).
if ! xcodebuild -project "$WORK/src/tvos/PhotomosaicTV.xcodeproj" -scheme PhotomosaicTV -configuration Release \
     -destination "id=$DEVICE" -derivedDataPath "$WORK/dd" \
     -allowProvisioningUpdates -allowProvisioningDeviceRegistration build > "$WORK/build.log" 2>&1; then
  for m in "${moved[@]}"; do mv "$WORK/old-profiles/$m" "$PROFILES/"; done   # put the old one back
  log "Build failed — is Xcode still signed in to your Apple ID? Details: $WORK/build.log"
  grep -m3 "error:" "$WORK/build.log" | sed 's/^/    /'
  exit 1
fi
expires=$(security cms -D -i "$APP/embedded.mobileprovision" | plutil -extract ExpirationDate raw -o - -)

# 5. Install (this closes the app if it's running).
if ! xcrun devicectl device install app --device "$DEVICE" "$APP" > "$WORK/install.log" 2>&1; then
  log "Install failed. Details: $WORK/install.log"
  exit 1
fi
version=$(xcrun devicectl device info apps --device "$DEVICE" --bundle-id "$BUNDLE" 2>/dev/null | tail -1 | awk '{print $3}')
log "Reinstalled Photomosaic $version on the Apple TV; good until $expires."
