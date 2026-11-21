#!/bin/zsh
# ProPlus watchdog, run every 30s (and at login) by launchd.
# Safety net in case ProPlus crashes or is force-quit while sleep is disabled:
#  - If sleep is disabled and ProPlus isn't running, or we're on battery, re-enable sleep.
#  - If we're on battery with the lid shut and still awake, put the Mac to sleep.

disabled=$(/usr/bin/pmset -g | /usr/bin/awk '/SleepDisabled/ {print $2}')
/usr/bin/pgrep -xq ProPlus && running=1 || running=0
/usr/bin/pmset -g ps | /usr/bin/head -1 | /usr/bin/grep -q "Battery Power" && battery=1 || battery=0

if [[ "$disabled" == "1" ]] && [[ $running == 0 || $battery == 1 ]]; then
  /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0 && /usr/bin/logger "ProPlus watchdog: re-enabled sleep"
  disabled=0
fi

if [[ $battery == 1 && "$disabled" != "1" ]] && \
   /usr/sbin/ioreg -r -k AppleClamshellState -d 1 | /usr/bin/grep -q '"AppleClamshellState" = Yes'; then
  /usr/bin/logger "ProPlus watchdog: lid closed on battery, sleeping"
  /usr/bin/pmset sleepnow
fi
