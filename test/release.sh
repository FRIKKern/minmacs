# ===== Release pipeline, issue #39: install.sh, uninstall.sh, release.sh and the cask =====
# Sourced by test.sh. Every install goes to a prefix inside $MINMACS_HOME, and HOME points into it too,
# so nothing reaches the person's ~/Applications or ~/.local/bin. The scripts never launch or stop an app
# for a prefix other than $HOME. release.sh runs with fake git and gh in front of PATH, which log each call.
# release.sh builds the app once. The hook runs package the build core made, through --app, to save two builds.
# It starts no process that outlives its command, so it adds nothing to procs.

rl="$MINMACS_HOME/release-$$"
rl_home="$rl/home"; rl_p="$rl/prefix"; rl_fake="$rl/fakebin"
mkdir -p "$rl_home" "$rl_p" "$rl_fake"
rl_want=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
rl_git=$(command -v git)

# The person's own install, read before and after, to show the section never touched it.
rl_real() {
  for f in "$HOME/Applications/MinMacs.app" "$HOME/.local/bin/minmacs" "$HOME/.local/bin/locohost"; do
    if [ -L "$f" ]; then printf 'link %s %s\n' "$f" "$(readlink "$f")"
    elif [ -e "$f" ]; then printf 'file %s %s\n' "$f" "$(stat -f %m "$f")"
    else printf 'none %s\n' "$f"; fi
  done
}
rl_sum() { rl_real | shasum -a 256 | awk '{print $1}'; }
rl_before=$(rl_sum)

rl_inst() { HOME="$rl_home" MINMACS_PREFIX= MINMACS_REF= ./install.sh --no-launch "$@" >"$rl/out.txt" 2>&1; }
rl_uninst() { HOME="$rl_home" MINMACS_PREFIX= MINMACS_PURGE= ./uninstall.sh "$@" >"$rl/out.txt" 2>&1; }
rl_id() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }

echo "-- the scripts"
for s in install.sh uninstall.sh release.sh; do
  sh -n "$s" 2>/dev/null
  check "release: $s parses" 0 "$?"
  check "release: $s is executable" yes "$([ -x "$s" ] && echo yes || echo no)"
done
check "release: release.sh runs no push, tag, commit or gh" 0 \
  "$(grep -nE '^[^#]*(git (push|tag|commit)|(^|[^a-z])gh )' release.sh | grep -c .)"

echo "-- install.sh from a local build"
rl_inst --app "$APP" --prefix "$rl_p"
rl_r=$?
check "release: install --app exits 0" 0 "$rl_r"
[ "$rl_r" = 0 ] || tail -5 "$rl/out.txt"
rl_dest="$rl_p/Applications/MinMacs.app"
check "release: the app is in <prefix>/Applications" no.guerrilla.minmacs "$(rl_id "$rl_dest" CFBundleIdentifier)"
check "release: the installed app has the build's version" "$rl_want" "$(rl_id "$rl_dest" CFBundleShortVersionString)"
check "release: the installed app is still signed" 0 "$(codesign --verify "$rl_dest" 2>/dev/null; echo $?)"
check "release: minmacs links to the app's binary" "$rl_dest/Contents/MacOS/MinMacs" "$(readlink "$rl_p/.local/bin/minmacs")"
check "release: locohost links to the same binary" "$rl_dest/Contents/MacOS/MinMacs" "$(readlink "$rl_p/.local/bin/locohost")"
check "release: minmacs version runs through the link" "MinMacs $rl_want (phase 1)" "$("$rl_p/.local/bin/minmacs" version 2>/dev/null)"
"$rl_p/.local/bin/locohost" help >"$rl/lh.txt" 2>&1
check "release: locohost help runs through its link" 0 "$?"
check "release: locohost help lists LocoHost 1.x commands" yes "$(grep -q '^ *locohost list' "$rl/lh.txt" && echo yes || echo no)"
check "release: the install says nothing was launched" yes "$(grep -q 'Nothing was launched' "$rl/out.txt" && echo yes || echo no)"

rl_inst --app "$APP" --prefix "$rl_p"
check "release: a second install over the first exits 0" 0 "$?"
check "release: the upgrade leaves no temporary copies" 0 "$(ls -A "$rl_p/Applications" | grep -c '^\.MinMacs')"
check "release: the upgrade leaves one app" 1 "$(ls "$rl_p/Applications" | grep -c .)"

echo "-- install.sh refuses what is not MinMacs"
rl_q="$rl/prefix-file"; mkdir -p "$rl_q/.local/bin"
printf 'standalone locohost\n' >"$rl_q/.local/bin/locohost"
rl_inst --app "$APP" --prefix "$rl_q"
check "release: install with a locohost file exits 0" 0 "$?"
check "release: a locohost file is left as it is" "standalone locohost" "$(cat "$rl_q/.local/bin/locohost")"
check "release: the install says it left the file" yes "$(grep -q 'is a file, not a link' "$rl/out.txt" && echo yes || echo no)"

rl_o="$rl/prefix-other"; mkdir -p "$rl_o/Applications/MinMacs.app/Contents"
cp Info.plist "$rl_o/Applications/MinMacs.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.example.other" "$rl_o/Applications/MinMacs.app/Contents/Info.plist"
rl_inst --app "$APP" --prefix "$rl_o"
check "release: install over another app's MinMacs.app fails" 1 "$?"
check "release: that app is left as it is" com.example.other "$(rl_id "$rl_o/Applications/MinMacs.app" CFBundleIdentifier)"
mkdir -p "$rl/notapp"
rl_inst --app "$rl/notapp" --prefix "$rl_p"
check "release: install of a folder that is not an app fails" 1 "$?"
rl_inst --app "$APP" --prefix "$rl/missing"
check "release: install to a prefix that does not exist fails" 1 "$?"

echo "-- release.sh"
cat >"$rl_fake/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$rl/git.log"
exec "$rl_git" "\$@"
EOF
cat >"$rl_fake/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$rl/gh.log"
exit 1
EOF
chmod +x "$rl_fake/git" "$rl_fake/gh"
: >"$rl/git.log"
rl_rel() { PATH="$rl_fake:$PATH" HOME="$rl_home" MINMACS_SIGN_HOOK="${rl_hook:-}" ./release.sh --no-tests --allow-dirty "$@" >"$rl/rel.txt" 2>&1; }

rl_out="$rl/out"
rl_hook="" rl_rel --out "$rl_out"
rl_r=$?
check "release: release.sh exits 0" 0 "$rl_r"
[ "$rl_r" = 0 ] || tail -8 "$rl/rel.txt"
rl_zip="MinMacs-$rl_want.zip"
for f in "$rl_zip" "$rl_zip.sha256" RELEASE_NOTES.md minmacs.rb release.txt; do
  check "release: release.sh writes $f" yes "$([ -s "$rl_out/$f" ] && echo yes || echo no)"
done
check "release: the build folder is gone from the release" no "$([ -e "$rl_out/build" ] && echo yes || echo no)"
check "release: shasum -c accepts the checksum" 0 "$(cd "$rl_out" && shasum -a 256 -c "$rl_zip.sha256" >/dev/null 2>&1; echo $?)"
rl_sha=$(shasum -a 256 "$rl_out/$rl_zip" | awk '{print $1}')
mkdir -p "$rl/unzip" && ditto -x -k "$rl_out/$rl_zip" "$rl/unzip"
check "release: the zip holds MinMacs.app at its top" "$rl_want" "$(rl_id "$rl/unzip/MinMacs.app" CFBundleShortVersionString)"
check "release: the zip's app is universal" "x86_64 arm64" "$(lipo -archs "$rl/unzip/MinMacs.app/Contents/MacOS/MinMacs" 2>/dev/null)"
check "release: the zip's app is signed" 0 "$(codesign --verify "$rl/unzip/MinMacs.app" 2>/dev/null; echo $?)"
check "release: the notes start with the version" "# MinMacs $rl_want" "$(head -1 "$rl_out/RELEASE_NOTES.md")"
check "release: the notes hold the changelog's section" yes "$(grep -q '^### Changed from LocoHost' "$rl_out/RELEASE_NOTES.md" && echo yes || echo no)"
check "release: the notes stop at the next version" 0 "$(grep -c '^## \[' "$rl_out/RELEASE_NOTES.md")"
check "release: the notes give the checksum" yes "$(grep -q "$rl_sha" "$rl_out/RELEASE_NOTES.md" && echo yes || echo no)"
check "release: the notes say the build is not notarized" yes "$(grep -q 'not notarized' "$rl_out/RELEASE_NOTES.md" && echo yes || echo no)"
check "release: release.txt names the version" "version=$rl_want" "$(grep '^version=' "$rl_out/release.txt")"
check "release: release.txt names the commit" "commit=$(git rev-parse HEAD)" "$(grep '^commit=' "$rl_out/release.txt")"
check "release: release.txt says build.sh made the app" "source=build.sh" "$(grep '^source=' "$rl_out/release.txt")"
check "release: release.txt says ad-hoc" "signing=ad-hoc, not notarized" "$(grep '^signing=' "$rl_out/release.txt")"
check "release: release.txt says the tests were skipped" "tests=skipped" "$(grep '^tests=' "$rl_out/release.txt")"

echo "-- the cask"
rl_cask="$rl_out/minmacs.rb"
check "release: the cask has the version" "version \"$rl_want\"" "$(grep -o 'version "[^"]*"' "$rl_cask" | head -1)"
check "release: the cask has the zip's checksum" "sha256 \"$rl_sha\"" "$(grep -o 'sha256 "[^"]*"' "$rl_cask")"
check "release: the cask names the zip release.sh made" yes \
  "$(grep -q 'releases/download/v#{version}/MinMacs-#{version}.zip' "$rl_cask" && echo yes || echo no)"
check "release: the cask has no placeholder left" 0 "$(grep -c '@[A-Z0-9_]*@' "$rl_cask")"
check "release: the cask links minmacs and locohost" 2 "$(grep -c '^ *binary .*target: "\(minmacs\|locohost\)"' "$rl_cask")"
check "release: the cask needs macOS 14" yes "$(grep -q 'depends_on macos: ">= :sonoma"' "$rl_cask" && echo yes || echo no)"
if [ -x /usr/bin/ruby ]; then
  check "release: the cask is valid Ruby" "Syntax OK" "$(/usr/bin/ruby -c "$rl_cask" 2>&1)"
fi

echo "-- release.sh publishes nothing"
check "release: release.sh never ran gh" no "$([ -s "$rl/gh.log" ] && echo yes || echo no)"
check "release: release.sh never ran git push, tag or commit" 0 "$(grep -cE '^(push|tag|commit)( |$)' "$rl/git.log")"
check "release: release.sh only read git" yes \
  "$([ -s "$rl/git.log" ] && ! grep -vqE '^(rev-parse|status)( |$)' "$rl/git.log" && echo yes || echo no)"

echo "-- release.sh refuses"
printf '# Changelog\n\n## [0.0.1] - 2020-01-01\n\n- Old.\n' >"$rl/CHANGELOG.md"
rl_hook="" rl_rel --out "$rl/out-nolog" --changelog "$rl/CHANGELOG.md"
check "release: no section for the version fails" 1 "$?"
check "release: and makes no zip" no "$([ -e "$rl/out-nolog/$rl_zip" ] && echo yes || echo no)"
mkdir -p "$rl/busy" && printf 'keep\n' >"$rl/busy/notes.txt"
rl_hook="" rl_rel --out "$rl/busy"
check "release: an out folder with other files fails" 1 "$?"
check "release: and its files stay" keep "$(cat "$rl/busy/notes.txt" 2>/dev/null)"

echo "-- the signing hook, issue #40"
rl_hook="$rl/hook.sh"
cat >"$rl_hook" <<EOF
#!/bin/sh
printf '%s %s\n' "\$1" "\$(basename "\$2")" >>"$rl/hook.log"
exit 0
EOF
chmod +x "$rl_hook"
rl_rel --out "$rl/out-hook" --app "$APP"
rl_r=$?
check "release: release.sh with a hook exits 0" 0 "$rl_r"
[ "$rl_r" = 0 ] || tail -8 "$rl/rel.txt"
check "release: the hook signs the app, then notarizes the zip" "sign MinMacs.app,notarize $rl_zip" \
  "$(paste -sd, "$rl/hook.log" 2>/dev/null)"
check "release: release.txt names a given app" "source=given: $APP" "$(grep '^source=' "$rl/out-hook/release.txt")"
check "release: release.txt says the hook ran" "signing=signed and notarized through the hook" "$(grep '^signing=' "$rl/out-hook/release.txt")"
printf '#!/bin/sh\nexit 3\n' >"$rl_hook"
rl_rel --out "$rl/out-badhook" --app "$APP"
check "release: a failing hook stops the release" 1 "$?"
check "release: and leaves no checksum" no "$([ -e "$rl/out-badhook/$rl_zip.sha256" ] && echo yes || echo no)"
rl_hook=""

echo "-- install.sh from the release zip"
rl_z="$rl/prefix-zip"; mkdir -p "$rl_z"
rl_inst --zip "$rl_out/$rl_zip" --prefix "$rl_z"
check "release: install --zip with its .sha256 exits 0" 0 "$?"
check "release: the zip's app is installed" "$rl_want" "$(rl_id "$rl_z/Applications/MinMacs.app" CFBundleShortVersionString)"
check "release: the zip install links minmacs" "MinMacs $rl_want (phase 1)" "$("$rl_z/.local/bin/minmacs" version 2>/dev/null)"
cp "$rl_out/$rl_zip" "$rl/$rl_zip"
rl_inst --zip "$rl/$rl_zip" --prefix "$rl_z"
check "release: a zip with no checksum is refused" 1 "$?"
rl_inst --zip "$rl/$rl_zip" --prefix "$rl_z" --sha256 0000000000000000000000000000000000000000000000000000000000000000
check "release: a zip with the wrong checksum is refused" 1 "$?"
check "release: the refusal names the mismatch" yes "$(grep -q 'checksum mismatch' "$rl/out.txt" && echo yes || echo no)"
rl_inst --zip "$rl/$rl_zip" --prefix "$rl_z" --sha256 "$rl_sha"
check "release: a zip with --sha256 exits 0" 0 "$?"

echo "-- uninstall.sh"
mkdir -p "$rl_p/Library/Application Support/MinMacs/locohost"
printf '{"kept":1}\n' >"$rl_p/Library/Application Support/MinMacs/locohost/rules.json"
ln -s /usr/bin/true "$rl_z/.local/bin/other"
rl_uninst --prefix "$rl_p"
check "release: uninstall exits 0" 0 "$?"
check "release: the app is gone" no "$([ -e "$rl_dest" ] && echo yes || echo no)"
check "release: the minmacs link is gone" no "$([ -L "$rl_p/.local/bin/minmacs" ] && echo yes || echo no)"
check "release: the locohost link is gone" no "$([ -L "$rl_p/.local/bin/locohost" ] && echo yes || echo no)"
check "release: the data stays without --purge" '{"kept":1}' "$(cat "$rl_p/Library/Application Support/MinMacs/locohost/rules.json" 2>/dev/null)"
check "release: uninstall says where the data stays" yes "$(grep -q 'Kept your data' "$rl/out.txt" && echo yes || echo no)"

rl_uninst --prefix "$rl_q"
check "release: uninstall leaves a locohost file" "standalone locohost" "$(cat "$rl_q/.local/bin/locohost" 2>/dev/null)"
ln -sf /usr/bin/true "$rl_z/.local/bin/locohost"
rl_uninst --prefix "$rl_z"
check "release: uninstall leaves a locohost link to something else" /usr/bin/true "$(readlink "$rl_z/.local/bin/locohost")"
check "release: uninstall leaves other links" /usr/bin/true "$(readlink "$rl_z/.local/bin/other")"
rl_uninst --prefix "$rl_o"
check "release: uninstall leaves another app's MinMacs.app" com.example.other "$(rl_id "$rl_o/Applications/MinMacs.app" CFBundleIdentifier)"

rl_uninst --prefix "$rl_p" --purge
check "release: uninstall --purge exits 0" 0 "$?"
check "release: --purge moves the data out" no "$([ -e "$rl_p/Library/Application Support/MinMacs" ] && echo yes || echo no)"
check "release: --purge puts the data in the prefix's Trash" '{"kept":1}' \
  "$(cat "$rl_p/.Trash/"MinMacs\ data*/locohost/rules.json 2>/dev/null)"

echo "-- nothing outside the prefix"
# build.sh runs python3, which keeps its bytecode in ~/Library/Caches/com.apple.python. Nothing else may be there.
check "release: the fake home stays empty" 0 \
  "$(find "$rl_home" -mindepth 1 | grep -vE "^$rl_home/Library(/Caches(/com\.apple\.python(/.*)?)?)?$" | grep -c .)"
check "release: the person's install is the same as before" "$rl_before" "$(rl_sum)"
