# Core checks: the build, the bundle and the CLI. Sourced by test.sh.
# test.sh always runs this section first, since it builds the copy the other sections test.

out=$(BUILD_DIR="$MINMACS_HOME/build" ./build.sh --no-install 2>&1); r=$?
check "build.sh builds into BUILD_DIR" 0 "$r"
[ "$r" = 0 ] || printf '%s\n' "$out" | tail -20
check "the build has no warnings" 0 "$(grep -c "warning:" "$MINMACS_HOME/build/clang.log" 2>/dev/null)"
check "the binary is universal" "x86_64 arm64" "$(lipo -archs "$BIN" 2>/dev/null)"
check "the binary targets macOS 14" "14.0" "$(vtool -arch arm64 -show-build "$BIN" 2>/dev/null | awk '/minos/ {print $2}')"
codesign --verify "$APP" 2>/dev/null
check "the bundle is signed" 0 "$?"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null; }
check "Info.plist has the bundle id" no.guerrilla.minmacs "$(plist CFBundleIdentifier)"
check "Info.plist has LSUIElement" true "$(plist LSUIElement)"
check "Info.plist has the macOS 14 floor" 14.0 "$(plist LSMinimumSystemVersion)"
want=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
rows=$(ls "$APP/Contents/Resources/registry/agents" 2>/dev/null | wc -l | tr -d ' ')
check "the registry ships with the app" yes "$([ "$rows" -gt 0 ] && echo yes || echo no)"

"$BIN" version >/dev/null 2>&1
check "minmacs version exits 0" 0 "$?"
check "minmacs version prints the bundle version" "MinMacs $want (phase 1)" "$("$BIN" version 2>/dev/null)"
mkdir -p "$MINMACS_HOME/bin" && ln -sf "$BIN" "$MINMACS_HOME/bin/minmacs"
check "it works through a symlink, as installed" "MinMacs $want (phase 1)" "$("$MINMACS_HOME/bin/minmacs" version 2>/dev/null)"
"$BIN" no-such-verb >/dev/null 2>&1
check "an unknown verb exits 2" 2 "$?"
