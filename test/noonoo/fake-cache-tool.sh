#!/bin/sh
# A fake cleanup tool for test/noonoo.sh, installed in $MINMACS_TOOLS under a name unique to the run, as the fixture
# rows name it. It acts only on $NN_FAKE_DIR, which must sit inside $MINMACS_HOME.
#   cache clean --dry-run   says what it would free, as Docker does: "Total reclaimed space: <n>kB"
#   cache clean             removes the files in $NN_FAKE_DIR/cache and says what it freed
#   prune                   removes the files in $NN_FAKE_DIR/nodry, with no dry-run form
# NN_FAKE_MODE=dryfail makes the dry run exit 4. NN_FAKE_MODE=slow makes the command write its pid to
# $NN_FAKE_DIR/slow.pid and then become $NN_FAKE_SLEEPER for 30 seconds, so the test sees its time limit stop it.
# The test builds that sleeper from test/insomnia/sleeper.c under a name unique to the run.
case "$NN_FAKE_DIR" in "$MINMACS_HOME"/*) ;; *) echo "fake tool: not a fixture folder" >&2; exit 3 ;; esac
kb() { du -sk "$1" 2>/dev/null | awk '{print $1}'; }
case "$*" in
  "cache clean --dry-run")
    [ "$NN_FAKE_MODE" = dryfail ] && { echo "fake tool: the dry run failed" >&2; exit 4; }
    echo "Would remove $(find "$NN_FAKE_DIR/cache" -type f | wc -l | tr -d ' ') files"
    echo "Total reclaimed space: $(kb "$NN_FAKE_DIR/cache")kB"
    exit 0 ;;
  "cache clean")
    if [ "$NN_FAKE_MODE" = slow ]; then echo $$ >"$NN_FAKE_DIR/slow.pid"; [ -x "$NN_FAKE_SLEEPER" ] || exit 5; exec "$NN_FAKE_SLEEPER" 30; fi
    n=$(kb "$NN_FAKE_DIR/cache")
    find "$NN_FAKE_DIR/cache" -type f -exec rm {} +
    echo "Total reclaimed space: ${n}kB"
    exit 0 ;;
  "prune")
    find "$NN_FAKE_DIR/nodry" -type f -exec rm {} +
    echo "pruned"
    exit 0 ;;
esac
echo "fake tool: unknown command: $*" >&2
exit 2
