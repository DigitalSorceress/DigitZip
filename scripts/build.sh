#!/bin/zsh
# Regenerates the Xcode project from project.yml and builds DigitZip (Debug) into ./build.
# Usage: scripts/build.sh [--install]   (--install copies the app to ~/Applications and launches it)
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
command -v 7zz >/dev/null || { echo "Install 7-Zip first: brew install sevenzip"; exit 1; }

xcodegen generate --quiet
xcodebuild -project DigitZip.xcodeproj -scheme DigitZip -configuration Debug \
  -derivedDataPath build -allowProvisioningUpdates build | grep -E "error|warning:|BUILD" || true

APP="build/Build/Products/Debug/DigitZip.app"
[ -d "$APP" ] || { echo "Build failed."; exit 1; }
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  pkill -x DigitZip 2>/dev/null || true
  rm -rf ~/Applications/DigitZip.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/DigitZip.app
  echo "Installed to ~/Applications/DigitZip.app"
fi
