#!/bin/zsh
# Builds ProPlus.app and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.1.2"
APP="build/ProPlus.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp watchdog.sh "$APP/Contents/Resources/watchdog.sh"
chmod 755 "$APP/Contents/Resources/watchdog.sh"

swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/ProPlus" Sources/main.swift

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ProPlus</string>
  <key>CFBundleIdentifier</key><string>local.haje.proplus</string>
  <key>CFBundleExecutable</key><string>ProPlus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"

mkdir -p ~/Applications
pkill -x ProPlus 2>/dev/null || true
rm -rf ~/Applications/ProPlus.app
cp -R "$APP" ~/Applications/
# Watchdog LaunchAgent: re-enables sleep if ProPlus dies while sleep is disabled.
LABEL="local.haje.proplus.watchdog"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF2
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/zsh</string><string>$HOME/Applications/ProPlus.app/Contents/Resources/watchdog.sh</string></array>
  <key>StartInterval</key><integer>30</integer>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF2
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

open ~/Applications/ProPlus.app
echo "Installed ~/Applications/ProPlus.app (v${VERSION}) and watchdog"
