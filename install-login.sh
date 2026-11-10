#!/bin/zsh
# Starts Balance in the menu bar (no window) at every login.
APP=~/Applications/Balance.app
PL=~/Library/LaunchAgents/com.sthavir.balance.plist
cat > "$PL" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.sthavir.balance</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/Balance</string><string>--background</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
launchctl bootstrap gui/$(id -u) "$PL" 2>/dev/null || true
echo "login item installed"
