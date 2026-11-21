#!/bin/zsh
# ProPlus watchdog, run every 30s (and at login) by launchd.
# Safety net in case ProPlus crashes, hangs or is force-quit while sleep is disabled:
#  - If sleep is disabled and ProPlus isn't running, or we're on battery, re-enable sleep.
#  - If we're on battery with the lid shut and still awake, put the Mac to sleep.

flag() { /usr/sbin/ioreg -r -c IOPMrootDomain -d 1 | /usr/bin/grep -q "\"$1\" = Yes"; }

/usr/bin/pmset -g ps | /usr/bin/grep -q "Battery Power" && battery=1 || battery=0

if flag SleepDisabled && { [[ $battery == 1 ]] || ! /usr/bin/pgrep -xq ProPlus; }; then
  /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 && /usr/bin/logger "ProPlus watchdog: re-enabled sleep"
fi

if [[ $battery == 1 ]] && flag AppleClamshellState && ! flag SleepDisabled; then
  /usr/bin/logger "ProPlus watchdog: lid closed on battery, sleeping"
  /usr/bin/pmset sleepnow
fi
