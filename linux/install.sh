#!/usr/bin/env bash
# Install / uninstall the watchdog for the current user (no root).
#   ./install.sh                 install (or update) and enable the timer
#   ./install.sh --uninstall     remove script and units, keep config + state
#   ./install.sh --purge         uninstall and also delete config + state
#   ./install.sh --dry-run ...   print what would happen
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$HOME/.local/bin"
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
conf="${XDG_CONFIG_HOME:-$HOME/.config}/grok-bot-watchdog"
state="${XDG_STATE_HOME:-$HOME/.local/state}/grok-bot-watchdog"
DRY=0 MODE=install
for a in "$@"; do
  case "$a" in
    --uninstall) MODE=uninstall ;;
    --purge) MODE=purge ;;
    --dry-run) DRY=1 ;;
    *) echo "usage: $0 [--uninstall|--purge] [--dry-run]" >&2; exit 2 ;;
  esac
done
run() { echo "+ $*"; (( DRY )) || "$@"; }

if [[ $MODE != install ]]; then
  run systemctl --user disable --now grok-bot-watchdog.timer 2>/dev/null || true
  run rm -f "$units/grok-bot-watchdog.service" "$units/grok-bot-watchdog.timer" "$bin/grok-bot-ensure"
  run systemctl --user daemon-reload
  [[ $MODE == purge ]] && run rm -rf "$conf" "$state"
  echo "$MODE done"
  exit 0
fi

# Previous versions are kept in the state dir, not next to your files.
if [[ -e "$bin/grok-bot-ensure" ]] && ! cmp -s "$bin/grok-bot-ensure" "$here/grok-bot-ensure"; then
  run mkdir -p "$state/previous"
  run cp -a "$bin/grok-bot-ensure" "$state/previous/grok-bot-ensure.$(date +%Y%m%d-%H%M%S)"
fi
run mkdir -p "$bin" "$units" "$conf" "$state"
run install -m 0755 "$here/grok-bot-ensure" "$bin/grok-bot-ensure"
run install -m 0644 "$here/systemd/grok-bot-watchdog.service" "$here/systemd/grok-bot-watchdog.timer" "$units/"
if [[ ! -e "$conf/config" ]]; then
  run install -m 0644 "$here/config.example" "$conf/config"
fi
run systemctl --user daemon-reload
run systemctl --user enable --now grok-bot-watchdog.timer
echo "installed. config: $conf/config   check: systemctl --user list-timers grok-bot-watchdog.timer"
