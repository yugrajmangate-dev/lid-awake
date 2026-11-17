#!/bin/bash
launchctl bootout "gui/$(id -u)/local.lidawake" 2>/dev/null
sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null || sudo pmset -a disablesleep 0
pkill -x LidAwake; rm -rf "$HOME/Applications/LidAwake.app" "$HOME/Library/LaunchAgents/local.lidawake.plist"
sudo rm -f /etc/sudoers.d/lidawake; echo Removed.
