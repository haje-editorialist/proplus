# ProPlus

A small macOS menu bar app that keeps a MacBook awake with the lid closed when it's plugged in to power and Claude is running, so Claude tasks keep going while the laptop is put away.

## Modes

Pick a mode from the menu bar icon (☕ = stays awake with lid closed, 🌙 = normal sleep):

- **On**: stay awake whenever plugged in
- **Auto** (default): stay awake when plugged in **and** the Claude desktop app is open
- **Off**: sleep when the lid closes

On battery, normal lid-close sleep is always restored. Quitting ProPlus restores it too.

## Safety nets

- **Lid already shut when sleep comes back** (e.g. you unplug with the lid closed): ProPlus puts the Mac to sleep right away, unless an external display is keeping it in clamshell mode.
- **Watchdog**: a LaunchAgent (`local.haje.proplus.watchdog`, installed by `build.sh`) runs every 30 seconds and at login. If ProPlus has crashed or been force-quit while sleep is off, or the Mac is on battery, it turns sleep back on, and sleeps the Mac if the lid is shut on battery.

## Install

```bash
./build.sh   # compiles and installs to ~/Applications/ProPlus.app
./setup.sh   # one time, asks for your admin password
```

`setup.sh` adds `/etc/sudoers.d/proplus`, which lets ProPlus run only `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password. It writes and validates the rule in a root-owned staging file before moving it into place. Undo with `sudo rm /etc/sudoers.d/proplus`.

To remove the watchdog: `launchctl bootout gui/$(id -u)/local.haje.proplus.watchdog && rm ~/Library/LaunchAgents/local.haje.proplus.watchdog.plist`.

Tick **Open at Login** in the menu to start it automatically.

## Changing it

Edit `Sources/main.swift`, bump `VERSION` in `build.sh`, then run `./build.sh`.
