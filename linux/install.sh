#!/usr/bin/env bash
# Install / uninstall the watchdog for the current user (no root).
#   ./install.sh            install + enable timer
#   ./install.sh --uninstall
#   ./install.sh --dry-run
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$HOME/.local/bin"
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
DRY=0 UN=0
for a in "$@"; do
  case "$a" in
    --uninstall) UN=1 ;;
    --dry-run) DRY=1 ;;
    *) echo "usage: $0 [--uninstall] [--dry-run]" >&2; exit 2 ;;
  esac
done
run() { echo "+ $*"; (( DRY )) || "$@"; }

if (( UN )); then
  run systemctl --user disable --now grok-bot-watchdog.timer || true
  run rm -f "$units/grok-bot-watchdog.service" "$units/grok-bot-watchdog.timer" "$bin/grok-bot-ensure"
  run systemctl --user daemon-reload
  echo "uninstalled (state left in ~/.local/state/grok-bot-watchdog)"
  exit 0
fi

ts=$(date +%Y%m%d-%H%M%S)
for f in "$bin/grok-bot-ensure" "$units/grok-bot-watchdog.service" "$units/grok-bot-watchdog.timer"; do
  if [[ -e "$f" ]] && ! cmp -s "$f" "$here/${f##*/}" 2>/dev/null && ! cmp -s "$f" "$here/systemd/${f##*/}" 2>/dev/null; then
    run cp -a "$f" "$f.bak-$ts"
  fi
done
run mkdir -p "$bin" "$units"
run install -m 0755 "$here/grok-bot-ensure" "$bin/grok-bot-ensure"
run install -m 0644 "$here/systemd/grok-bot-watchdog.service" "$here/systemd/grok-bot-watchdog.timer" "$units/"
run systemctl --user daemon-reload
run systemctl --user enable --now grok-bot-watchdog.timer
echo "installed. check: systemctl --user list-timers grok-bot-watchdog.timer"
