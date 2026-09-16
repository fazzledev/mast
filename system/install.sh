#!/bin/bash
# Installs the site block and the helper the bar toggles it with:
#   sudo bash ~/.dotfiles/system/site-block/install.sh
# Idempotent. Leaves every site blocked. See uninstall.sh to undo.

set -euo pipefail

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=/usr/local/bin/site-block

[[ $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }
say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# This used to be YouTube-only, as block-youtube. Clear that out so the two
# cannot leave overlapping hosts entries or conflicting policies behind.
if [[ -e /usr/local/bin/block-youtube ]] || grep -qxF '# >>> block-youtube >>>' /etc/hosts; then
  say "Removing the old block-youtube install"
  sed -i '/^# >>> block-youtube >>>$/,/^# <<< block-youtube <<<$/d' /etc/hosts
  rm -f /etc/chromium/policies/managed/block-youtube.json
  rm -f /etc/opt/chrome/policies/managed/block-youtube.json
  rm -f /usr/local/bin/block-youtube
fi

# Copied, not symlinked: the bar runs this as root through pkexec, so it must
# be root-owned and out of reach of this user-writable repo. Re-run after edits.
# No sudoers rule on purpose -- lifting a block always asks for auth.
say "Installing $BIN"
install -o root -g root -m 0755 "$SRC_DIR/site-block" "$BIN"

say "Blocking every site"
"$BIN" on all
"$BIN" status
