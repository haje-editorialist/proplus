#!/bin/zsh
# Builds ProPlus.app and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.0.0"
APP="build/ProPlus.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS"

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
echo "Installed ~/Applications/ProPlus.app (v${VERSION})"
