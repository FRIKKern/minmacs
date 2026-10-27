#!/bin/sh
# A fake tmux CLI for test/locohost.sh. The section copies it into its fixture folder. list-panes prints tmux.panes
# from that folder, and every other command is recorded there, so no real tmux session is made or read.
D=$(dirname "$0")
case "$1" in
  list-panes) cat "$D/tmux.panes" 2>/dev/null ;;
  list-clients) : ;;
  *) printf '%s\n' "$*" >>"$D/tmux.goto" ;;
esac
exit 0
