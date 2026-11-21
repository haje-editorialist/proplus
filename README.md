# ProPlus

A small macOS menu bar app that keeps a MacBook awake with the lid closed when it's plugged in to power and Claude is running, so Claude tasks keep going while the laptop is put away.

**Why "ProPlus"?** It's named after Pro Plus, the caffeine tablets that kept me going through my university days. This app does the same job for the laptop.

## Modes

Pick a mode from the menu bar icon (☕ = stays awake with lid closed, 🌙 = normal sleep):

- **On**: stay awake whenever plugged in
- **Auto** (default): stay awake when plugged in **and** the Claude desktop app is open
- **Off**: sleep when the lid closes

On battery, normal lid-close sleep is always restored. Quitting ProPlus restores it too.

## Safety nets

- **Lock when lid closes**: because the Mac doesn't sleep, it wouldn't lock either. ProPlus locks the screen the moment you close the lid while it's keeping the Mac awake. Untick **Lock When Lid Closes** in the menu to turn this off. (Uses the same unofficial system call as the Lock Screen menu item, since macOS has no public one.)
- **Laptop Temperature**: the menu shows the laptop temperature level (Normal, Warm, Hot, Very hot), from macOS's own thermal rating. If it reaches Hot with the lid shut, ProPlus lets the Mac sleep and the icon turns into a thermometer. It stays that way until you open the lid.
- **Lid already shut when sleep comes back** (e.g. you unplug with the lid closed): ProPlus puts the Mac to sleep right away, unless an external display is keeping it in clamshell mode.
- **Watchdog**: a LaunchAgent (`local.haje.proplus.watchdog`, installed by `build.sh`) runs every 30 seconds and at login. If sleep is off and ProPlus has crashed or been force-quit, or the Mac is on battery, it turns sleep back on, and sleeps the Mac if the lid is shut on battery.

## Known limits

- The sleep-off setting is saved by macOS and survives a restart. A normal restart or shutdown quits ProPlus, which turns sleep back on. After a hard power-off or a system crash, sleep stays off until you log in again (the watchdog then fixes it within seconds).
- ProPlus owns the `disablesleep` setting: it will switch it back if another tool changes it.
- An external or virtual display (AirPlay, Sidecar) counts as "using the Mac with the lid shut", so ProPlus won't lock, force sleep or apply the overheat check while one is connected.

## Install

Needs macOS 13 or later and the Xcode command line tools (`xcode-select --install`).

```bash
./build.sh   # compiles, installs to ~/Applications/ProPlus.app, loads the watchdog
./setup.sh   # one time, asks for your admin password
```

`setup.sh` adds `/etc/sudoers.d/proplus`, which lets ProPlus run only `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password. It writes and validates the rule in a root-owned staging file before moving it into place.

Tick **Open at Login** in the menu to start it automatically.

## Uninstall

```bash
./uninstall.sh   # asks for your admin password
```

Removes the app, the watchdog, the saved mode and the `/etc/sudoers.d/proplus` rule, and puts lid-close sleep back to normal.

## Changing it

Edit `Sources/main.swift`, bump `VERSION` in `build.sh`, then run `./build.sh`.
