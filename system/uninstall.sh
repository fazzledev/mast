#!/bin/bash
# Unblocks YouTube and removes the helper. Run as root:
#   sudo bash ~/.dotfiles/system/block-youtube/uninstall.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }

# Lift the block before removing the tool that lifts it.
bash "$(dirname "${BASH_SOURCE[0]}")/block-youtube" off
rm -f /usr/local/bin/block-youtube

echo "removed; YouTube is unblocked and the bar widget hides itself"
