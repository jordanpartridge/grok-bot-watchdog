#!/usr/bin/env bash
# UNTESTED macOS installer.  ./install.sh [--uninstall]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
label=com.github.grok-bot-watchdog
plist="$HOME/Library/LaunchAgents/$label.plist"
if [[ "${1:-}" == --uninstall ]]; then
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  rm -f "$plist" "$HOME/.local/bin/grok-bot-ensure-macos"
  echo uninstalled; exit 0
fi
mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents"
install -m 0755 "$here/grok-bot-ensure-macos" "$HOME/.local/bin/"
sed "s#__HOME__#$HOME#g" "$here/$label.plist" >"$plist"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "installed: launchctl print gui/$(id -u)/$label"
