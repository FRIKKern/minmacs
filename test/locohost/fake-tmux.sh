#!/bin/sh
# A fake tmux CLI for test/locohost.sh. The section copies it into its fixture folder. list-panes prints tmux.panes
# from that folder, and every other command is recorded there, so no real tmux session is made or read.
# A file tmux.slow holding a number makes every other command take that many seconds, as a busy tmux or a permission
# prompt can. A file, since MinMacs runs tmux with a clean environment.
D=$(dirname "$0")
case "$1" in
  list-panes) cat "$D/tmux.panes" 2>/dev/null ;;
  list-clients) : ;;
  *) printf '%s\n' "$*" >>"$D/tmux.goto"; [ -s "$D/tmux.slow" ] && sleep "$(cat "$D/tmux.slow")" ;;
esac
exit 0
