# Builds test/quiet/tool.m once per run, for test/device.sh and test/quiet.sh. Sourced by either section.
# All of Core, the kit, the CLI and the experts under -DMM_TESTS, as the app has them but for the shell. Sets DQ.
dq_dir="$MINMACS_HOME/dq"
DQ="$dq_dir/tool"
if [ ! -x "$DQ" ]; then
  mkdir -p "$dq_dir"
  dq_cc="clang -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -DMM_TESTS -ISources"
  # shellcheck disable=SC2046
  $dq_cc $(find Sources -name '*.m' ! -path 'Sources/main.m' ! -path 'Sources/Shell/*' | LC_ALL=C sort) test/quiet/tool.m \
    -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
    -o "$DQ" >"$dq_dir/build.log" 2>&1
  dq_r=$?
  check "the device and quiet test tool builds" 0 "$dq_r"
  check "Core, the CLI and the experts have no warnings under -Wextra" 0 "$(grep -c 'warning:' "$dq_dir/build.log")"
  [ "$dq_r" = 0 ] || tail -20 "$dq_dir/build.log"
fi
