#!/usr/bin/env bash
# macOS installer.  ./install.sh [--uninstall|--purge]
#   --uninstall  remove the LaunchAgent and script, keep config/state/logs
#   --purge      also delete config, state and logs
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
label=com.github.grok-bot-watchdog
plist="$HOME/Library/LaunchAgents/$label.plist"
conf="$HOME/.config/grok-bot-watchdog"
case "${1:-}" in
  --uninstall|--purge)
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    rm -f "$plist" "$HOME/.local/bin/grok-bot-ensure-macos"
    [[ "$1" == --purge ]] && rm -rf "$conf" "$HOME/Library/Application Support/grok-bot-watchdog" "$HOME/Library/Logs/grok-bot-watchdog"
    echo "${1#--} done"; exit 0 ;;
  "") ;;
  *) echo "usage: $0 [--uninstall|--purge]" >&2; exit 2 ;;
esac
mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/grok-bot-watchdog" "$conf"
install -m 0755 "$here/grok-bot-ensure-macos" "$HOME/.local/bin/"
[[ -e "$conf/config" ]] || install -m 0644 "$here/config.example" "$conf/config"
sed "s#__HOME__#$HOME#g" "$here/$label.plist" >"$plist"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "installed: launchctl print gui/$(id -u)/$label"
