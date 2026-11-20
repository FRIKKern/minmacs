# Issue #116: git's own files are bytes. Sourced by test/git.sh, after the tool is built, with gq, gc, gf and check.
# One repo per case, each with a bare origin, a main checkout and one linked worktree on a branch named for the case,
# so one case's packed-refs or config never reaches another's. Every fixture lies in $MINMACS_HOME/git/bytes.
# APFS refuses a file name that is not UTF-8 ("Illegal byte sequence"), so a loose ref with such a name cannot be
# made here: those names live in packed-refs, which git writes on a clone, and in HEAD, config and the stash log.

GY="$G/bytes"; mkdir -p "$GY/roots" "$GY/nul-config" "$GY/nul-head" "$GY/nul-gitfile"
GYR="$GY/roots"
FFFD=$(printf '\357\277\275')   # U+FFFD, how a byte that is not UTF-8 shows
# gy_case <root> <case> merged|open: a worktree <root>/<case>/wt on branch <case>, pushed with an upstream. merged
# leaves it at main's tip; open adds one commit, pushed and not merged. Every ref is then packed, as after a clone.
gy_case() {
  gy_c="$1/$2"; mkdir -p "$gy_c"
  gq init -q --bare "$gy_c/origin.git"; gq clone -q "$gy_c/origin.git" "$gy_c/main"
  gc "$gy_c/main" base.txt base base; gq -C "$gy_c/main" push -q -u origin main; gq -C "$gy_c/main" remote set-head origin main
  gq -C "$gy_c/main" worktree add -q -b "$2" "$gy_c/wt" main
  [ "$3" = open ] && gc "$gy_c/wt" open.txt open open
  gq -C "$gy_c/wt" push -q -u origin "$2"
  gq -C "$gy_c/main" pack-refs --all
}
# A stash log line by hand, for what git does not write itself: <common> <subject bytes as printf takes them> [end]
gy_stash_line() { printf "%s %s fixture <f@example.invalid> 1700000000 +0000\t$2${3-\\n}" \
  0000000000000000000000000000000000000000 "$(git -C "$1" rev-parse HEAD)" >>"$1/.git/logs/refs/stash"; }
gy_bytes() { od -An -tx1 "$1" | tr -d ' \n'; }   # a file's bytes as hex, to show the fixture holds what it says
gy_has() { case "$(gy_bytes "$1")" in *"$2"*) echo yes ;; *) echo no ;; esac; }

echo "-- a stash log that is not UTF-8 still counts every stash, issue #116"
gy_case "$GYR" z merged   # the control: no stash log at all
gy_case "$GYR" a merged
printf 'x\n' >>"$GYR/a/wt/base.txt"
gq -C "$GYR/a/wt" -c i18n.commitEncoding=ISO-8859-1 stash push -q -m "$(printf 'caf\351')"
check "bytes: git wrote the stash message in Latin-1" yes "$(gy_has "$GYR/a/main/.git/logs/refs/stash" 636166e90a)"
gy_case "$GYR" b merged
printf 'x\n' >>"$GYR/b/wt/base.txt"
GIT_COMMITTER_NAME="$(printf 'Jos\351')" git -C "$GYR/b/wt" stash push -q -m plain >/dev/null 2>&1
check "bytes: git wrote the stash's author in Latin-1" yes "$(gy_has "$GYR/b/main/.git/logs/refs/stash" 4a6f73e9)"

echo "-- packed-refs with names that are not UTF-8"
gy_case "$GYR" c open
python3 - "$GYR/c/main/.git/packed-refs" "$(git -C "$GYR/c/main" rev-parse main)" <<'PYEOF'
import sys
p, sha = sys.argv[1], sys.argv[2].encode()
lines = open(p, 'rb').read().split(b'\n')
lines[0] = lines[0].replace(b' sorted', b'')   # git then reads the file in full, with no binary search
lines[1:1] = [sha + b' refs/heads/caf\xe9', sha + b' refs/remotes/origin/caf\xe9']
open(p, 'wb').write(b'\n'.join(lines))
PYEOF
check "bytes: git reads the Latin-1 refs and the worktree's own" "2|origin/c" \
  "$(git -C "$GYR/c/main" for-each-ref --format='%(refname)' | LC_ALL=C grep -c "$(printf 'caf\351')")|$(gt_up "$GYR/c/wt")"

echo "-- a config with a Latin-1 value and section name"
gy_case "$GYR" d open
printf '[user]\n\tname = Jos\351\n[branch "caf\351"]\n\tremote = origin\n\tmerge = refs/heads/caf\351\n' >>"$GYR/d/main/.git/config"
check "bytes: git still reads the upstream" origin/d "$(gt_up "$GYR/d/wt")"

echo "-- HEAD on a branch whose name is not UTF-8"
gy_case "$GYR" e merged
gc "$GYR/e/wt" e.txt e "on no remote"
gq -C "$GYR/e/main" pack-refs --all
python3 - "$GYR/e/main/.git/packed-refs" <<'PYEOF'
import sys
p = sys.argv[1]
d = open(p, 'rb').read().replace(b' sorted', b'', 1).replace(b' refs/heads/e\n', b' refs/heads/caf\xe9\n')
open(p, 'wb').write(d)
PYEOF
printf 'ref: refs/heads/caf\351\n' >"$GYR/e/main/.git/worktrees/wt/HEAD"
gy_stash_line "$GYR/e/main" 'On caf\351: by hand'
check "bytes: git reads HEAD there, with 1 commit on no remote" "$(git -C "$GYR/e/main" rev-parse "$(printf 'caf\351')")|1" \
  "$(git -C "$GYR/e/wt" rev-parse HEAD)|$(git -C "$GYR/e/wt" rev-list --count HEAD --not --remotes)"

echo "-- files with a NUL byte, CRLF lines, no trailing newline or a UTF-8 BOM"
gy_case "$GYR" f1 merged
gy_stash_line "$GYR/f1/main" 'On f1: a\000b'
gy_case "$GYR" f2 open
python3 -c "import sys; p=sys.argv[1]; d=open(p,'rb').read(); open(p,'wb').write(d.replace(b'\n', b'\r\n'))" "$GYR/f2/main/.git/config"
check "bytes: git reads a CRLF config" origin/f2 "$(gt_up "$GYR/f2/wt")"
gy_case "$GYR" f3 merged
gy_stash_line "$GYR/f3/main" 'On f3: one' '\r\n'; gy_stash_line "$GYR/f3/main" 'WIP on f3: two' ''
gy_case "$GYR" f4 open
printf 'x\n' >>"$GYR/f4/wt/base.txt"; gq -C "$GYR/f4/wt" stash push -q -m bom
for f in config logs/refs/stash; do
  python3 -c "import sys; p=sys.argv[1]; d=open(p,'rb').read(); open(p,'wb').write(b'\xef\xbb\xbf' + d)" "$GYR/f4/main/.git/$f"
done
check "bytes: git reads a config with a BOM" origin/f4 "$(gt_up "$GYR/f4/wt")"
gy_case "$GYR" f5 open
python3 -c "import sys; p=sys.argv[1]; d=open(p,'rb').read(); open(p,'wb').write(d.rstrip(b'\n'))" "$GYR/f5/main/.git/config"
check "bytes: git reads a config with no trailing newline" origin/f5 "$(gt_up "$GYR/f5/wt")"

echo "-- a file that is there and cannot be read"
gy_case "$GYR" g1 merged
mkdir -p "$GYR/g1/main/.git/logs/refs"; mkfifo "$GYR/g1/main/.git/logs/refs/stash"
gy_case "$GYR" g2 merged
python3 -c "import sys; open(sys.argv[1], 'wb').truncate(257 << 20)" "$GYR/g2/main/.git/logs/refs/stash"   # sparse
gy_case "$GYR" g3 merged
printf 'x\n' >>"$GYR/g3/wt/base.txt"; gq -C "$GYR/g3/wt" stash push -q -m locked
chmod 000 "$GYR/g3/main/.git/logs/refs/stash"
gy_case "$GYR" g4 open
chmod 000 "$GYR/g4/main/.git/packed-refs"
gy_case "$GYR" g6 open
chmod 000 "$GYR/g6/main/.git/worktrees/wt/HEAD"

echo "-- a NUL byte where a path is built"
gy_case "$GY/nul-config" n1 open
python3 -c "import sys; p=sys.argv[1]; d=open(p,'rb').read(); open(p,'wb').write(d.replace(b'merge = refs/heads/n1', b'merge = refs/heads/n1\x00x'))" \
  "$GY/nul-config/n1/main/.git/config"
check "bytes: git reads the upstream up to the NUL" origin/n1 "$(gt_up "$GY/nul-config/n1/wt")"
gy_case "$GY/nul-head" n2 open
printf 'ref: refs/heads/n2\000x\n' >"$GY/nul-head/n2/main/.git/worktrees/wt/HEAD"
gy_case "$GY/nul-gitfile" n3 open
gq -C "$GY/nul-gitfile/n3/main" worktree add -q -b n3b "$GY/nul-gitfile/n3/wt2" main
printf 'gitdir: %s\000x\n' "$GY/nul-gitfile/n3/main/.git/worktrees/wt2" >"$GY/nul-gitfile/n3/wt2/.git"

GO=$("$GT" keeps "$GYR")
gy() { gf "$GYR/$1/wt" "$2"; }
check "bytes: a Latin-1 stash message counts" "1|it has 1 stash" "$(gy a stashes)|$(gy a smart)"
check "bytes: a stash by a Latin-1 author counts" "1|it has 1 stash" "$(gy b stashes)|$(gy b smart)"
check "bytes: Latin-1 names in packed-refs leave the others" "$(git -C "$GYR/c/wt" rev-parse HEAD)|origin/main|0" \
  "$(gy c head)|$(gy c defaultBranch)|$(gy c unpushed)"
check "  so the remote branch is not gone and the branch stays" \
  "origin/c|False|none|its branch is not merged and its remote branch still exists" \
  "$(gy c upstream)|$(gy c upstreamGone)|$(gy c merged)|$(gy c smart)"
check "bytes: a Latin-1 config still gives the upstream" "origin/d|False|0/0" \
  "$(gy d upstream)|$(gy d upstreamGone)|$(gy d ahead)/$(gy d behind)"
check "bytes: a branch name that is not UTF-8 shows, with U+FFFD" "caf$FFFD|caf$FFFD" "$(gy e indexBranch)|$(gy e branch)"
check "  its HEAD is not known, so its commits are not counted as 0" "None|-1|-1|none" \
  "$(gy e head)|$(gy e unpushed)|$(gy e notInDefault)|$(gy e merged)"
check "  its stash counts, and Smart keeps a way back" "1|cannot verify what git holds of it" "$(gy e stashes)|$(gy e smart)"
check "bytes: a NUL byte in a stash line counts" 1 "$(gy f1 stashes)"
check "bytes: a CRLF config gives the upstream, not gone" "origin/f2|False|its branch is not merged and its remote branch still exists" \
  "$(gy f2 upstream)|$(gy f2 upstreamGone)|$(gy f2 smart)"
check "bytes: CRLF stash lines and no trailing newline count" 2 "$(gy f3 stashes)"
check "bytes: a BOM in config and stash log" "origin/f4|1" "$(gy f4 upstream)|$(gy f4 stashes)"
check "bytes: a config with no trailing newline" "origin/f5|False" "$(gy f5 upstream)|$(gy f5 upstreamGone)"
check "bytes: a stash log that is a named pipe is not known, and keeps" "-1|cannot verify what git holds of it" \
  "$(gy g1 stashes)|$(gy g1 smart)"
check "bytes: a stash log past the cap is not known, and keeps" "-1|cannot verify what git holds of it" \
  "$(gy g2 stashes)|$(gy g2 smart)"
check "bytes: a stash log that cannot be opened is not known, and keeps" "-1|cannot verify what git holds of it" \
  "$(gy g3 stashes)|$(gy g3 smart)"
check "bytes: packed-refs that cannot be opened: HEAD not known, the remote branch not gone" "None|-1|origin/g4|False" \
  "$(gy g4 head)|$(gy g4 unpushed)|$(gy g4 upstream)|$(gy g4 upstreamGone)"
check "bytes: a HEAD that cannot be opened: nothing counted as 0" "None|-1|-1" \
  "$(gy g6 head)|$(gy g6 unpushed)|$(gy g6 stashes)"
check "bytes: a repo with no stash log has 0 stashes" "0|0" "$(gy z stashes)|$(gy c stashes)"
check "  and a merged clean worktree with none is Smart's to delete" "delete now" "$(gy z smart)"

GO=$("$GT" keeps "$GY/nul-config"); gy_st=$?
check "bytes: a NUL in config's merge value: the remote branch is not gone" "0|False" \
  "$gy_st|$(gf "$GY/nul-config/n1/wt" upstreamGone 2>/dev/null)"
GO=$("$GT" keeps "$GY/nul-head"); gy_st=$?
check "bytes: a NUL in HEAD: HEAD is not known" "0|None|-1" \
  "$gy_st|$(gf "$GY/nul-head/n2/wt" head 2>/dev/null)|$(gf "$GY/nul-head/n2/wt" unpushed 2>/dev/null)"
GO=$("$GT" keeps "$GY/nul-gitfile"); gy_st=$?
check "bytes: a NUL in a .git file: the walk ends and finds the others" "0|0" \
  "$gy_st|$(gf "$GY/nul-gitfile/n3/wt" unpushed 2>/dev/null)"
check "bytes: MMGitDirsOf reads no commondir that cannot be opened as a submodule's" None \
  "$(chmod 000 "$GYR/g1/main/.git/worktrees/wt/commondir"; "$GT" dirs "$GYR/g1/wt" | json "j['dirs']"; chmod 644 "$GYR/g1/main/.git/worktrees/wt/commondir")"
chmod 644 "$GYR/g3/main/.git/logs/refs/stash" "$GYR/g4/main/.git/packed-refs" "$GYR/g6/main/.git/worktrees/wt/HEAD"
