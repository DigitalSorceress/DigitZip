#!/bin/zsh
# Regenerates the Xcode project from project.yml and builds DigitZip (Debug) into ./build.
# Usage: scripts/build.sh [--install]   (--install copies the app to ~/Applications and launches it)
#
# Signing comes from Config/Local.xcconfig. With CODE_SIGN_STYLE = Manual, Xcode builds
# unsigned and this script signs with CODE_SIGN_IDENTITY using codesign directly. That's
# needed for self-made Keychain certificates, which Xcode's own signing step rejects.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
command -v 7zz >/dev/null || { echo "Install 7-Zip first: brew install sevenzip"; exit 1; }

LOCAL=Config/Local.xcconfig
setting() { [[ -f $LOCAL ]] && sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1/p" $LOCAL | tail -1; }
STYLE="$(setting CODE_SIGN_STYLE || true)"
IDENTITY="$(setting CODE_SIGN_IDENTITY || true)"

xcodegen generate --quiet

XCODE_ARGS=(-project DigitZip.xcodeproj -scheme DigitZip -configuration Debug -derivedDataPath build)
if [[ $STYLE == Manual ]]; then
  [[ -n $IDENTITY ]] || { echo "Set CODE_SIGN_IDENTITY in $LOCAL"; exit 1; }
  XCODE_ARGS+=(CODE_SIGNING_ALLOWED=NO)
else
  XCODE_ARGS+=(-allowProvisioningUpdates)
fi

LOG=build/xcodebuild.log
mkdir -p build
if ! xcodebuild "${XCODE_ARGS[@]}" build >$LOG 2>&1; then
  grep -E "error:" $LOG | sort -u || true
  echo "Build failed. Full log: $LOG"
  exit 1
fi
grep -E "warning:" $LOG | grep -v appintentsmetadataprocessor | sort -u || true

APP="build/Build/Products/Debug/DigitZip.app"
APPEX="$APP/Contents/PlugIns/DigitZipFinder.appex"

if [[ $STYLE == Manual ]]; then
  # Sign inside-out: nested code first, the app bundle last.
  sign() { codesign --force --timestamp=none --sign "$IDENTITY" "$@" >/dev/null; }
  for f in "$APP"/Contents/MacOS/*(.N) "$APPEX"/Contents/MacOS/*.dylib(.N); do
    [[ $f == "$APP/Contents/MacOS/DigitZip" ]] || sign "$f"
  done
  sign --entitlements FinderExtension/DigitZipFinder.entitlements "$APPEX"
  sign --entitlements App/DigitZip.entitlements "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "Built and signed $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST=~/Applications/DigitZip.app
  pkill -x DigitZip 2>/dev/null || true
  mkdir -p ~/Applications
  rm -rf $DEST
  cp -R "$APP" $DEST
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $DEST
  pluginkit -a $DEST/Contents/PlugIns/DigitZipFinder.appex
  open $DEST
  echo "Installed to $DEST"
fi
