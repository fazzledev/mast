#!/bin/bash
# Installs the YouTube block and the helper the bar toggles it with:
#   sudo bash ~/.dotfiles/system/block-youtube/install.sh
# Idempotent. Leaves YouTube blocked. See uninstall.sh to undo.

set -euo pipefail

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=/usr/local/bin/block-youtube

[[ $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }
say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# Copied, not symlinked: the bar runs this as root through pkexec, so it must
# be root-owned and out of reach of this user-writable repo. Re-run after edits.
# No sudoers rule on purpose -- flipping the block always asks for auth.
say "Installing $BIN"
install -o root -g root -m 0755 "$SRC_DIR/block-youtube" "$BIN"

say "Blocking YouTube"
"$BIN" on
"$BIN" status
