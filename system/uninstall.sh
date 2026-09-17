#!/bin/bash
# Unblocks every site and removes the helper. Run as root:
#   sudo bash system/uninstall.sh

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }

# Lift the blocks before removing the tool that lifts them.
bash "$(dirname "${BASH_SOURCE[0]}")/site-block" off all
# `off` arms relock timers; with the helper going away they have nothing to run.
for unit in $(systemctl list-units --all --plain --no-legend 'site-block-relock-*' | awk '{print $1}'); do
  systemctl stop "$unit" 2>/dev/null || true
done
rm -rf /var/lib/site-block
systemctl disable site-block-restore.service 2>/dev/null || true
rm -f /etc/systemd/system/site-block-restore.service
systemctl daemon-reload
rm -f /usr/local/bin/site-block
rm -f /etc/polkit-1/rules.d/50-site-block.rules

echo "removed; nothing is blocked and the bar widget hides itself"
