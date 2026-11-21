#!/bin/zsh
# One-time setup: lets ProPlus toggle lid-close sleep without asking for a password.
# It only permits these two exact commands:
#   /usr/bin/pmset -a disablesleep 0
#   /usr/bin/pmset -a disablesleep 1
# Undo with: sudo rm /etc/sudoers.d/proplus
#
# The rule is written straight into a root-owned staging file and checked there,
# so nothing running as you can swap its contents between the check and the install.
# (sudo ignores files in sudoers.d whose names contain a ".", so the staging file is inert.)
set -euo pipefail

USER_NAME="$(id -un)"
if [[ ! "$USER_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Unexpected username: $USER_NAME" >&2
  exit 1
fi

STAGE="/etc/sudoers.d/.proplus.staging"
FINAL="/etc/sudoers.d/proplus"

printf '%s ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n' "$USER_NAME" \
  | sudo /usr/bin/tee "$STAGE" >/dev/null
sudo /bin/chmod 0440 "$STAGE"
sudo /usr/sbin/chown root:wheel "$STAGE"
if ! sudo /usr/sbin/visudo -cf "$STAGE"; then
  sudo /bin/rm -f "$STAGE"
  echo "Rule failed validation; nothing installed." >&2
  exit 1
fi
sudo /bin/mv -f "$STAGE" "$FINAL"
echo "Done. ProPlus can now switch lid-close sleep on and off."
