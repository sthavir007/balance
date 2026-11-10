#!/bin/zsh
# Builds ~/Applications/Balance.app (signed with the Apple Development cert when present)
# Run ./install-login.sh once to start the menu bar readout at login.
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
APP=~/Applications/Balance.app
[ -f AppIcon.icns ] || { swift make-icon.swift . ; iconutil -c icns AppIcon.iconset -o AppIcon.icns; rm -rf AppIcon.iconset; }
pkill -x Balance 2>/dev/null || true
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -target arm64-apple-macos15.0 App.swift Store.swift -o "$APP/Contents/MacOS/Balance"
cp AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.sthavir.balance</string>
  <key>CFBundleName</key><string>Balance</string>
  <key>CFBundleDisplayName</key><string>Balance</string>
  <key>CFBundleExecutable</key><string>Balance</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Balance reads your Apple Watch numbers from the Health Sync note.</string>
</dict></plist>
PLIST
SIGN_ID=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | awk '{print $2}')
codesign --force -s "${SIGN_ID:--}" "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "built $APP"
