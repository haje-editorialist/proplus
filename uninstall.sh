#!/bin/zsh
# Removes ProPlus completely: the app, the watchdog, its saved mode, and the
# password-free pmset rule. Asks for your admin password to remove the rule.
set -uo pipefail

LABEL="local.haje.proplus.watchdog"

echo "Stopping the watchdog..."
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"

echo "Quitting ProPlus..."
pkill -x ProPlus 2>/dev/null
sleep 1

echo "Restoring normal sleep and removing the admin rule (needs your password)..."
sudo /usr/bin/pmset -a disablesleep 0
sudo /bin/rm -f /etc/sudoers.d/proplus /etc/sudoers.d/.proplus.staging

echo "Removing the app and its settings..."
rm -rf "$HOME/Applications/ProPlus.app"
defaults delete local.haje.proplus 2>/dev/null

echo "Done. ProPlus is uninstalled and lid-close sleep is back to normal."
echo "If ProPlus still shows under System Settings > General > Login Items, remove it there."
