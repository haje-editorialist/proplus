#!/bin/zsh
# One-time setup: lets ProPlus toggle lid-close sleep without asking for a password.
# It only permits these two exact commands:
#   /usr/bin/pmset -a disablesleep 0
#   /usr/bin/pmset -a disablesleep 1
# Undo with: sudo rm /etc/sudoers.d/proplus
set -euo pipefail

USER_NAME="$(id -un)"
TMP="$(mktemp)"
cat > "$TMP" <<EOF
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
EOF

sudo visudo -cf "$TMP"
sudo install -m 0440 -o root -g wheel "$TMP" /etc/sudoers.d/proplus
rm -f "$TMP"
echo "Done. ProPlus can now switch lid-close sleep on and off."
