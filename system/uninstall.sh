#!/bin/bash
# Unblocks every site and removes the helper. Run as root:
#   sudo bash system/uninstall.sh
#
# Leaves the bar widget and your record alone: the widget then shows the line
# that puts the helper back, and `mast-db reasons` still has your answers.

set -euo pipefail

# Everything hangs off MAST_PREFIX, which is empty in an install and a
# temporary directory under test (see test/system).
PREFIX=${MAST_PREFIX:-}
[[ $EUID -eq 0 || -n $PREFIX ]] || { echo "run me with sudo" >&2; exit 1; }

# Lift the blocks before removing the tool that lifts them.
bash "$(dirname "${BASH_SOURCE[0]}")/mast" off all
# `off` arms relock timers; with the helper going away they have nothing to run.
for unit in $(systemctl list-units --all --plain --no-legend 'mast-relock-*' | awk '{print $1}'); do
  systemctl stop "$unit" 2>/dev/null || true
done
rm -rf "$PREFIX/var/lib/mast"
systemctl disable mast-restore.service 2>/dev/null || true
rm -f "$PREFIX/etc/systemd/system/mast-restore.service"
systemctl daemon-reload
rm -f "$PREFIX/usr/local/bin/mast"
rm -f "$PREFIX/etc/polkit-1/rules.d/50-mast.rules"

echo "removed; nothing is blocked"
echo "the bar widget stays, and shows the line that installs the helper again"
