#!/bin/bash
# Unblocks every site and removes the helper. Run as root:
#   sudo bash ~/.dotfiles/system/site-block/uninstall.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }

# Lift the blocks before removing the tool that lifts them.
bash "$(dirname "${BASH_SOURCE[0]}")/site-block" off all
rm -f /usr/local/bin/site-block
rm -f /etc/polkit-1/rules.d/50-site-block.rules

echo "removed; nothing is blocked and the bar widget hides itself"
