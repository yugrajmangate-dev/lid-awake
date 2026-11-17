#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="build/LidAwake.app"; rm -rf build; mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/LidAwake" src/main.swift
mkdir -p "$APP/Contents/Resources"; TMP=$(mktemp -d)
swiftc -o "$TMP/icon" src/icon.swift && "$TMP/icon" "$TMP/AppIcon.iconset" && iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.lidawake</string>
<key>CFBundleName</key><string>LidAwake</string>
<key>CFBundleExecutable</key><string>LidAwake</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
P
codesign --force --sign - "$APP"
echo "Built $APP"
