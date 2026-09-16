#!/bin/bash
# Installs the site block and the helper the bar toggles it with:
#   sudo bash ~/.dotfiles/system/site-block/install.sh [SITE...]
# Idempotent, and leaves existing blocks as they are; name sites to block
# them as well (e.g. `youtube twitter`). See uninstall.sh to undo.

set -euo pipefail

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=/usr/local/bin/site-block
RULE=/etc/polkit-1/rules.d/50-site-block.rules
UNIT=/etc/systemd/system/site-block-restore.service
TARGET_USER=${SUDO_USER:-$(logname 2>/dev/null || echo "")}

[[ $EUID -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }
[[ -n $TARGET_USER ]] || { echo "could not determine the target user" >&2; exit 1; }
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
say "Installing $BIN"
install -o root -g root -m 0755 "$SRC_DIR/site-block" "$BIN"

# Blocking should be free; only unblocking should cost a prompt. pkexec passes
# the full command line to polkit, so this lets exactly `site-block on <name>`
# through for the logged-in user at the seat. The helper rejects names it does
# not know, so the pattern does not need to track the site list. `off` still
# falls through to polkit's default and asks for auth.
say "Installing $RULE for $TARGET_USER"
cat >"$RULE" <<RULEFILE
// Installed by ~/.dotfiles/system/site-block/install.sh
polkit.addRule(function(action, subject) {
  if (action.id == "org.freedesktop.policykit.exec" &&
      action.lookup("program") == "$BIN" &&
      /^\\/usr\\/local\\/bin\\/site-block on [a-z]+\$/.test(action.lookup("command_line")) &&
      subject.user == "$TARGET_USER" && subject.local && subject.active) {
    return polkit.Result.YES;
  }
});
RULEFILE
chmod 0644 "$RULE"

# Relock timers are transient and die with a reboot; this puts them back.
say "Installing $UNIT"
cat >"$UNIT" <<'UNITFILE'
[Unit]
Description=Re-arm or apply site-block relocks after boot
ConditionDirectoryNotEmpty=/var/lib/site-block

[Service]
Type=oneshot
ExecStart=/usr/local/bin/site-block restore

[Install]
WantedBy=multi-user.target
UNITFILE
systemctl daemon-reload
systemctl enable site-block-restore.service

for site in "$@"; do
  say "Blocking $site"
  "$BIN" on "$site"
done

say "Current state"
"$BIN" status
