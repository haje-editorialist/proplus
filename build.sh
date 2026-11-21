#!/bin/zsh
# Builds ProPlus.app, installs it to ~/Applications, and loads the watchdog LaunchAgent.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.3.0"
APP="build/ProPlus.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 755 watchdog.sh "$APP/Contents/Resources/"

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
while pgrep -xq ProPlus; do sleep 0.2; done   # let it finish quitting before relaunching
rm -rf ~/Applications/ProPlus.app
cp -R "$APP" ~/Applications/

# Watchdog LaunchAgent: re-enables sleep if ProPlus dies while sleep is disabled.
LABEL="local.haje.proplus.watchdog"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
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
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

open ~/Applications/ProPlus.app
echo "Installed ~/Applications/ProPlus.app (v${VERSION}) and watchdog"
