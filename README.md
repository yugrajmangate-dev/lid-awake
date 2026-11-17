# LidAwake

A tiny macOS menu bar app that keeps your MacBook running with the **lid closed** — no external monitor needed. Handy for long renders, builds, downloads and terminal automation.

- **Menu bar only** — no Dock icon. Laptop icon = normal sleep; filled coffee cup (+ time left) = staying awake.
- **One-click toggle, no repeated password prompts** (one-time setup, see below).
- **Safety timers** — 2 h, 4 h, 8 h or indefinite. Timers survive app restarts and reboots.
- **Low-battery safety** — automatically restores sleep on battery below 10 / 20 / 30 % (event-driven, no polling).
- **Always accurate** — reads the real system state (`pmset`), so it stays correct if you change it from Terminal or after a restart.
- **Tiny** — ~11 MB memory, 0.0 % CPU and ~1 wake-up per minute when idle. Native Swift/SwiftUI, no dependencies.
- Optional launch at login (toggle in the panel).

## Requirements

- macOS 13 or newer (Apple Silicon or Intel)
- Xcode Command Line Tools (`xcode-select --install`) — the app is built from source
- An administrator account (needed once for setup)

## Install

```bash
git clone https://github.com/yugrajmangate-dev/lid-awake.git
cd lid-awake
./install.sh
```

The installer builds the app, copies it to `~/Applications`, starts it, and asks for your admin password **once**.

Then click the laptop icon in the menu bar.

### What the installer changes (so you can review it)

1. Installs `~/Applications/LidAwake.app` (ad-hoc signed, built locally).
2. Adds `/etc/sudoers.d/lidawake`, validated with `visudo`, allowing admin users to run **only** these two exact commands without a password:
   ```
   /usr/bin/pmset -a disablesleep 0
   /usr/bin/pmset -a disablesleep 1
   ```
3. Adds a login item at `~/Library/LaunchAgents/local.lidawake.plist`.

Everything is in `install.sh` and `src/main.swift` (~300 lines) — read them before running.

## Usage

Click the menu bar icon → flip the switch. Pick a timer first (or after, to reset it). Quitting the app restores normal sleep.

> **Heat warning:** don't leave a heavily loaded MacBook closed inside a bag or sleeve — it can overheat.

## Uninstall

```bash
./uninstall.sh
```

Restores normal sleep, removes the app, login item and sudoers rule.

## How it works

`pmset -a disablesleep 1` tells macOS not to sleep when the lid closes. It needs root, hence the narrow sudoers rule. The state is read back from `pmset -g` (`SleepDisabled`).

## Windows

This tool is macOS-only. Windows has a built-in setting instead: *Control Panel → Power Options → "Choose what closing the lid does" → Do nothing*. From a terminal:

```powershell
powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
powercfg /setactive SCHEME_CURRENT
```

(Set the value back to `1` for sleep.) These commands are provided for convenience and are not part of this app.

## Contributing

Issues and PRs welcome — ideas: custom menu bar icons, notifications when a timer ends, a Homebrew cask.

## License

MIT
