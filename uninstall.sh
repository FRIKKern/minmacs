#!/bin/sh
# Removes MinMacs completely: app, CLI link, preferences, rules, login item.
#   curl -fsSL https://raw.githubusercontent.com/FRIKKern/minmacs/main/uninstall.sh | sh
set -u
say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
if pgrep -x MinMacs >/dev/null 2>&1; then
  say "Stopping MinMacs"; open "minmacs://login-off" 2>/dev/null; sleep 1; open "minmacs://quit" 2>/dev/null || pkill -x MinMacs; sleep 1
fi
rm -rf "$HOME/Applications/MinMacs.app" "/Applications/MinMacs.app" "$HOME/.local/bin/minmacs" "$HOME/Library/Application Support/MinMacs" 2>/dev/null
defaults delete no.guerrilla.minmacs >/dev/null 2>&1
say "MinMacs removed."
