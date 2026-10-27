#!/bin/sh
# A fake tmux CLI for the Know checks. list-panes prints tmux.panes from its own folder. Other commands are recorded.
D=$(dirname "$0")
case "$1" in
  list-panes) cat "$D/tmux.panes" 2>/dev/null ;;
  list-clients) : ;;
  *) printf '%s\n' "$*" >>"$D/tmux.goto" ;;
esac
exit 0
