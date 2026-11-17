#!/bin/bash
# Run once:  ./install.sh   (asks for your admin password ONCE for the sudoers rule)
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
DEST="$HOME/Applications"; mkdir -p "$DEST"
pkill -x LidAwake 2>/dev/null || true
rm -rf "$DEST/LidAwake.app"; cp -R build/LidAwake.app "$DEST/"

# Narrow rule: only these two exact commands, no password.
TMP=$(mktemp)
cat > "$TMP" <<R
%admin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
R
sudo visudo -cf "$TMP"
sudo install -m 0440 -o root -g wheel "$TMP" /etc/sudoers.d/lidawake
rm -f "$TMP"

# Start at login
mkdir -p "$HOME/Library/LaunchAgents"
PL="$HOME/Library/LaunchAgents/local.lidawake.plist"
cat > "$PL" <<P
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>local.lidawake</string>
<key>ProgramArguments</key><array><string>$DEST/LidAwake.app/Contents/MacOS/LidAwake</string></array>
<key>RunAtLoad</key><true/></dict></plist>
P
launchctl bootout "gui/$(id -u)/local.lidawake" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PL"
echo "Installed. Look for the laptop icon in the menu bar."
