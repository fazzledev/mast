#!/bin/bash
# Installs Mast's site block and the root helper the bar toggles it with:
#   sudo bash system/install.sh [SITE...]
# Idempotent, and leaves existing blocks as they are. Name sites to block them
# (e.g. `youtube twitter`); with none named, and nothing blocked yet, it asks.
# See uninstall.sh to undo.

set -euo pipefail

SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Everything hangs off MAST_PREFIX, which is empty in an install and a
# temporary directory under test (see test/system).
PREFIX=${MAST_PREFIX:-}
BIN=$PREFIX/usr/local/bin/mast
RULE=$PREFIX/etc/polkit-1/rules.d/50-mast.rules
UNIT=$PREFIX/etc/systemd/system/mast-restore.service
TARGET_USER=${SUDO_USER:-$(logname 2>/dev/null || echo "")}

[[ $EUID -eq 0 || -n $PREFIX ]] || { echo "run me with sudo" >&2; exit 1; }
[[ -n $TARGET_USER ]] || { echo "could not determine the target user" >&2; exit 1; }
say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# This used to be YouTube-only, as block-youtube. Clear that out so the two
# cannot leave overlapping hosts entries or conflicting policies behind.
if [[ -e $PREFIX/usr/local/bin/block-youtube ]] || grep -qxF '# >>> block-youtube >>>' "$PREFIX/etc/hosts"; then
  say "Removing the old block-youtube install"
  sed -i '/^# >>> block-youtube >>>$/,/^# <<< block-youtube <<<$/d' "$PREFIX/etc/hosts"
  rm -f "$PREFIX/etc/chromium/policies/managed/block-youtube.json"
  rm -f "$PREFIX/etc/opt/chrome/policies/managed/block-youtube.json"
  rm -f "$PREFIX/usr/local/bin/block-youtube"
fi

# Before Mast had its name, the helper was site-block. Note what it was doing
# -- which sites were blocked, and how long each unblock had left -- then
# clear it out, so the two cannot leave overlapping hosts entries, conflicting
# policies or stray timers behind. The new helper picks up where it left off
# once installed, below.
was_blocked=()
was_relocking=()
if [[ -e $PREFIX/usr/local/bin/site-block ]] || grep -q '^# >>> site-block:' "$PREFIX/etc/hosts"; then
  say "Moving the site-block install over to mast"
  mapfile -t was_blocked < <(sed -n 's/^# >>> site-block:\([a-z]*\) >>>$/\1/p' "$PREFIX/etc/hosts")
  now=$(date +%s)
  for f in "$PREFIX"/var/lib/site-block/*.until; do
    [[ -r $f ]] || continue
    was_relocking+=("$(basename "$f" .until):$(( $(cat "$f") - now ))")
  done
  for unit in $(systemctl list-units --all --plain --no-legend 'site-block-relock-*' | awk '{print $1}'); do
    systemctl stop "$unit" 2>/dev/null || true
  done
  sed -i '/^# >>> site-block:[a-z]* >>>$/,/^# <<< site-block:[a-z]* <<<$/d' "$PREFIX/etc/hosts"
  rm -f "$PREFIX/etc/chromium/policies/managed/site-block.json" "$PREFIX/etc/opt/chrome/policies/managed/site-block.json"
  rm -rf "$PREFIX/var/lib/site-block"
  systemctl disable site-block-restore.service 2>/dev/null || true
  rm -f "$PREFIX/etc/systemd/system/site-block-restore.service" "$PREFIX/etc/polkit-1/rules.d/50-site-block.rules" "$PREFIX/usr/local/bin/site-block"
fi

# Copied, not symlinked: the bar runs this as root through pkexec, so it must
# be root-owned and out of reach of this user-writable repo. Re-run after edits.
say "Installing $BIN"
install -d -m 0755 "$(dirname "$BIN")"
if [[ -n $PREFIX ]]; then
  install -m 0755 "$SRC_DIR/mast" "$BIN"
else
  install -o root -g root -m 0755 "$SRC_DIR/mast" "$BIN"
fi

# Blocking should be free; only unblocking should cost a prompt. pkexec passes
# the full command line to polkit, so this lets exactly `mast on <name>`
# through for the logged-in user at the seat. The helper rejects names it does
# not know, so the pattern does not need to track the site list. `off` still
# falls through to polkit's default and asks for auth.
say "Installing $RULE for $TARGET_USER"
install -d -m 0755 "$(dirname "$RULE")"
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
install -d -m 0755 "$(dirname "$UNIT")"
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

# A fresh install blocks nothing, and the widget's default switches -- YouTube
# and X -- are a guess at what anyone wants. Ask once, here, where the answer
# can be acted on straight away. Skipped when sites were named as arguments,
# when something is blocked already (so a re-run does not nag), and when there
# is nobody to ask. MAST_ASK=yes forces it, for the tests.
asked=${MAST_ASK:-auto}
if [[ $# -eq 0 && $asked != no ]] && { [[ $asked == yes ]] || [[ -t 0 ]]; } &&
   command -v gum >/dev/null && [[ -z $("$BIN" status | awk -F'\t' '$3 == 1 { print $1 }') ]]; then
  # The hint goes in gum's own header: anything echoed before it is wiped by
  # the picker taking over the screen, so nobody ever reads it.
  say "Which sites should Mast block?"
  # gum 2.0 toggles with x, not space, and shows its own keybinds with
  # --show-help; the header says it too, since that is what people read. It
  # also says the choice is not final: nothing here is worth deliberating over
  # when every site is a switch in the bar afterwards.
  chosen=$(gum choose --no-limit --height 12 --show-help \
    --header "Every one is a switch in the bar afterwards, so you can change this later.
x picks · a picks all · up/down moves · enter confirms · esc picks none" \
    --cursor "> " --selected-prefix "[x] " --unselected-prefix "[ ] " \
    $("$BIN" status | cut -f1) || true)
  for site in $chosen; do
    "$BIN" on "$site"
  done
fi

say "Current state"
"$BIN" status

# The panel that sent you here is still showing the line you just ran, so open
# it on the sites instead. Opening it takes the keyboard, which is fine when it
# is the last thing your own command does -- the widget never does it by
# itself. sudo strips the session, so hand the shell back what it needs to find
# it. Best effort: no shell, no widget, no harm.
if command -v omarchy-shell >/dev/null && [[ -n $TARGET_USER ]]; then
  runuser -u "$TARGET_USER" -- env \
    XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
    OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}" \
    omarchy-shell -q fazzledev.mast open >/dev/null 2>&1 || true
fi
