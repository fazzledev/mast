#!/bin/bash
# Installs Mast's site block and the root helper the bar toggles it with:
#   sudo bash system/install.sh [SITE...]
# Idempotent, and leaves existing blocks as they are; name sites to block
# them as well (e.g. `youtube twitter`). See uninstall.sh to undo.

set -euo pipefail

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=/usr/local/bin/mast
RULE=/etc/polkit-1/rules.d/50-mast.rules
UNIT=/etc/systemd/system/mast-restore.service
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

# Before Mast had its name, the helper was site-block. Note what it was doing
# -- which sites were blocked, and how long each unblock had left -- then
# clear it out, so the two cannot leave overlapping hosts entries, conflicting
# policies or stray timers behind. The new helper picks up where it left off
# once installed, below.
was_blocked=()
was_relocking=()
if [[ -e /usr/local/bin/site-block ]] || grep -q '^# >>> site-block:' /etc/hosts; then
  say "Moving the site-block install over to mast"
  mapfile -t was_blocked < <(sed -n 's/^# >>> site-block:\([a-z]*\) >>>$/\1/p' /etc/hosts)
  now=$(date +%s)
  for f in /var/lib/site-block/*.until; do
    [[ -r $f ]] || continue
    was_relocking+=("$(basename "$f" .until):$(( $(cat "$f") - now ))")
  done
  for unit in $(systemctl list-units --all --plain --no-legend 'site-block-relock-*' | awk '{print $1}'); do
    systemctl stop "$unit" 2>/dev/null || true
  done
  sed -i '/^# >>> site-block:[a-z]* >>>$/,/^# <<< site-block:[a-z]* <<<$/d' /etc/hosts
  rm -f /etc/chromium/policies/managed/site-block.json /etc/opt/chrome/policies/managed/site-block.json
  rm -rf /var/lib/site-block
  systemctl disable site-block-restore.service 2>/dev/null || true
  rm -f /etc/systemd/system/site-block-restore.service /etc/polkit-1/rules.d/50-site-block.rules /usr/local/bin/site-block
fi

# Copied, not symlinked: the bar runs this as root through pkexec, so it must
# be root-owned and out of reach of this user-writable repo. Re-run after edits.
say "Installing $BIN"
install -o root -g root -m 0755 "$SRC_DIR/mast" "$BIN"

# Blocking should be free; only unblocking should cost a prompt. pkexec passes
# the full command line to polkit, so this lets exactly `mast on <name>`
# through for the logged-in user at the seat. The helper rejects names it does
# not know, so the pattern does not need to track the site list. `off` still
# falls through to polkit's default and asks for auth.
say "Installing $RULE for $TARGET_USER"
cat >"$RULE" <<RULEFILE
// Installed by Mast's system/install.sh
polkit.addRule(function(action, subject) {
  if (action.id == "org.freedesktop.policykit.exec" &&
      action.lookup("program") == "$BIN" &&
      /^\\/usr\\/local\\/bin\\/mast on [a-z]+\$/.test(action.lookup("command_line")) &&
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
Description=Re-arm or apply Mast relocks after boot
ConditionDirectoryNotEmpty=/var/lib/mast

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mast restore

[Install]
WantedBy=multi-user.target
UNITFILE
systemctl daemon-reload
systemctl enable mast-restore.service

# What site-block was doing, carried over: blocks stay on, and an unblock
# keeps the time it had left (a minute at least, the helper's cap at most).
for site in "${was_blocked[@]}"; do
  "$BIN" on "$site"
done
for entry in "${was_relocking[@]}"; do
  site=${entry%%:*} left=${entry#*:}
  if (( left <= 0 )); then
    "$BIN" on "$site"
  else
    minutes=$(( (left + 59) / 60 ))
    "$BIN" off "$site" $(( minutes > 60 ? 60 : minutes ))
  fi
done

for site in "$@"; do
  say "Blocking $site"
  "$BIN" on "$site"
done

say "Current state"
"$BIN" status
