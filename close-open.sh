#!/bin/bash
# Stop blocked sites that were already open when the block went on.
#   close-open.sh SITE...
#
# The hosts file and Chrome policy only catch new requests: a page already
# loaded keeps its connections, so a playing video plays on. So, in the user's
# session:
#   - web app windows for the site (Omarchy's chrome-<domain>__ apps) close;
#   - browser windows whose visible tab is on the site reload, once Chrome has
#     picked up the new policy, which lands them on the "blocked" page.
# Background tabs show no title to match and are left alone.

set -euo pipefail

# Chrome waits a few seconds after the policy directory changes before
# reloading it; a reload before then just loads the site again.
POLICY_SETTLE=${POLICY_SETTLE:-8}

app_class() {
  case $1 in
    youtube) echo '^chrome-((www|m|music)\.)?youtube\.com__' ;;
    twitter) echo '^chrome-((www|mobile)\.)?(x|twitter)\.com__' ;;
  esac
}

# Browser window titles are "<tab title> - Google Chrome" (or Chromium).
tab_title() {
  case $1 in
    youtube) echo ' - YouTube( Music)? - (Google Chrome|Chromium)$' ;;
    twitter) echo ' / X - (Google Chrome|Chromium)$' ;;
  esac
}

dispatch() { hyprctl dispatch "$1" >/dev/null; }

reload=()
clients=$(hyprctl clients -j)
for site in "$@"; do
  class=$(app_class "$site")
  title=$(tab_title "$site")
  [[ -n $class ]] || continue

  while read -r addr; do
    [[ -n $addr ]] && dispatch "hl.dsp.window.close({ window = \"address:$addr\" })"
  done < <(jq -r --arg re "$class" '.[] | select(.class | test($re)) | .address' <<<"$clients")

  while read -r addr; do
    [[ -n $addr ]] && reload+=("$addr")
  done < <(jq -r --arg re "$title" '.[] | select(.title | test($re)) | .address' <<<"$clients")
done

(( ${#reload[@]} )) || exit 0
sleep "$POLICY_SETTLE"
for addr in "${reload[@]}"; do
  # Down and up as separate dispatches: Hyprland's one-shot shortcut can leave
  # a synthetic key stuck repeating.
  dispatch "hl.dsp.send_key_state({ mods = \"\", key = \"F5\", state = \"down\", window = \"address:$addr\" })"
  dispatch "hl.dsp.send_key_state({ mods = \"\", key = \"F5\", state = \"up\", window = \"address:$addr\" })"
done
