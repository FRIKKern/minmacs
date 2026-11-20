# Issue #118: the upstream as git's own config reader gives it. Sourced by test/git.sh, after the tool is built, with
# gq, gc and check. One repo per row, each with a bare origin, a main checkout and one linked worktree on the row's
# branch, with one commit of its own that is pushed: clean, on a remote and not merged. So Smart deletes it only when
# its remote branch is gone, and a reading that makes a live upstream look gone shows as "delete now".
# Each row writes the branch's section, or the files around it, in one spelling git accepts or refuses, then compares
# what git answers with what MinMacs's facts say and what Smart decides on them. Every fixture lies in
# $MINMACS_HOME/git/config.

CF="$G/config"; CFR="$CF/roots"; mkdir -p "$CFR"
# cf_case <id> [branch]: the row's repo, its branch section removed. CFC is its config, CFD its folder.
cf_case() {
  CFD="$CFR/$1"; cf_b="${2:-$1}"; mkdir -p "$CFD"
  gq init -q --bare "$CFD/origin.git"; gq clone -q "$CFD/origin.git" "$CFD/main"
  gc "$CFD/main" base.txt base base; gq -C "$CFD/main" push -q -u origin main; gq -C "$CFD/main" remote set-head origin main
  gq -C "$CFD/main" worktree add -q -b "$cf_b" "$CFD/wt" main
  gc "$CFD/wt" open.txt open open
  gq -C "$CFD/wt" push -q -u origin "$cf_b"
  CFC="$CFD/main/.git/config"
  gq -C "$CFD/main" config --remove-section "branch.$cf_b"
}
# cf_sec <id> <body as printf takes it>: a new repo whose branch section is [branch "<id>"] with that body.
cf_sec() { cf_case "$1"; printf "[branch \"%s\"]\n$2" "$1" >>"$CFC"; }

echo "-- comments after a value"
cf_sec c1 '\tremote = origin\n\tmerge = refs/heads/c1 ; a note\n'
cf_sec c2 '\tremote = origin\n\tmerge = refs/heads/c2 # a note\n'
cf_sec c3 '\tremote = origin\n\tmerge = refs/heads/c3;note\n'
cf_sec c4 '\tremote = origin\n\tmerge = refs/heads/c4#note\n'
cf_sec c5 '\tremote = origin ; a note\n\tmerge = refs/heads/c5\n'
cf_sec c6 '\tremote = origin#note\n\tmerge = refs/heads/c6\n'

echo "-- quotes and escapes"
cf_sec q1 '\tremote = "origin"\n\tmerge = "refs/heads/q1"\n'
# What git itself writes for a branch whose name holds # or ; or ": git branch -u, after the section went.
for cf_q in 'q2:q#2' 'q3:q;3' 'e1:e"1'; do
  cf_case "${cf_q%%:*}" "${cf_q#*:}"; gq -C "$CFD/wt" branch -u "origin/${cf_q#*:}"
done
check "config: git writes # and ; in quotes, and \" as an escape" "yes|yes|yes" \
  "$(grep -qF 'merge = "refs/heads/q#2"' "$CFR/q2/main/.git/config" && echo yes || echo no)|$(grep -qF 'merge = "refs/heads/q;3"' "$CFR/q3/main/.git/config" && echo yes || echo no)|$(grep -qF 'merge = refs/heads/e\"1' "$CFR/e1/main/.git/config" && grep -qF '[branch "e\"1"]' "$CFR/e1/main/.git/config" && echo yes || echo no)"
cf_case q4 'q#4'; printf '[branch "q#4"]\n\tremote = origin\n\tmerge = refs/heads/"q#4"\n' >>"$CFC"
cf_sec e2 '\tremote = origin\n\tmerge = refs/heads/e2\\q\n'
cf_sec e3 '\tremote = origin\n\tmerge = "refs/heads/e3\\t"\n'
cf_sec e4 '\tremote = origin\n\tmerge = refs/heads/e4\\\\\n'
cf_sec e5 '\tremote = origin\n\tmerge = refs/heads/e5\\n\n'

echo "-- whitespace, continuation lines and bare keys"
cf_sec w1 '\tremote = origin \t \n\tmerge = refs/heads/w1 \t \n'
cf_sec w2 '\tremote\t=\torigin\t\n\tmerge\t=\trefs/heads/w2\t\n'
cf_sec w3 '\tremote = origin\n\tmerge = " refs/heads/w3"\n'
cf_sec k1 '\tremote = origin\n\tmerge = refs/heads/\\\nk1\n'
cf_sec k2 '\tremote = ori\\\ngin\n\tmerge = refs/heads/k2\n'
cf_sec s1 'remote=origin\nmerge=refs/heads/s1\n'
cf_sec v1 '\tremote = origin\n\tmerge = refs/heads/v1\n\tmerge\n'
cf_sec v2 '\tremote = origin\n\tmerge =\n\tmerge = refs/heads/v2\n'

echo "-- section headers"
cf_case h1; printf '[BRANCH "h1"]\n\tremote = origin\n\tmerge = refs/heads/h1\n' >>"$CFC"
cf_case h2; printf '[branch "H2"]\n\tremote = origin\n\tmerge = refs/heads/h2\n' >>"$CFC"
cf_case h3; printf '[branch.h3]\n\tremote = origin\n\tmerge = refs/heads/h3\n' >>"$CFC"
cf_case h4 Up4; printf '[branch.Up4]\n\tremote = origin\n\tmerge = refs/heads/Up4\n' >>"$CFC"
cf_case h5; printf '[branch "h\\5"]\n\tremote = origin\n\tmerge = refs/heads/h5\n' >>"$CFC"
cf_case h6; printf '[branch "h6"] # a note\n\tremote = origin\n\tmerge = refs/heads/h6\n' >>"$CFC"
cf_case h7; printf '[branch "h7"] merge = refs/heads/h7\n\tremote = origin\n' >>"$CFC"
cf_case h8; printf '[branch\t "h8"]\n\tremote = origin\n\tmerge = refs/heads/h8\n' >>"$CFC"
cf_case h9; printf '[branch "h9" ]\n\tremote = origin\n\tmerge = refs/heads/h9\n' >>"$CFC"
cf_case h10; printf '[ branch "h10"]\n\tremote = origin\n\tmerge = refs/heads/h10\n' >>"$CFC"

echo "-- a key twice, a section twice, CRLF"
cf_sec d1 '\tremote = origin\n\tmerge = refs/heads/nothere\n\tmerge = refs/heads/d1\n'
cf_sec d2 '\tremote = origin\n\tmerge = refs/heads/d2\n\tmerge = refs/heads/nothere\n'
cf_sec d3 '\tremote = nothere\n\tremote = origin\n\tmerge = refs/heads/d3\n'
cf_sec d4 '\tremote = origin\n\tremote = nothere\n\tmerge = refs/heads/d4\n'
cf_sec d5 '\tremote = origin\n[core]\n\tbare = false\n[branch "d5"]\n\tmerge = refs/heads/d5\n'
cf_sec r1 '\tremote = origin\n\tmerge = refs/heads/r1 ; a note\n'
python3 -c "import sys; p=sys.argv[1]; d=open(p,'rb').read(); open(p,'wb').write(d.replace(b'\n', b'\r\n'))" "$CFC"

echo "-- the remote ., a tag, another ref and other fetch lines"
cf_sec l1 '\tremote = .\n\tmerge = refs/heads/main\n'
cf_sec l2 '\tremote = .\n\tmerge = main\n'
cf_case g1; gq -C "$CFD/main" tag v1; gq -C "$CFD/main" push -q origin v1
printf '[branch "g1"]\n\tremote = origin\n\tmerge = refs/tags/v1\n' >>"$CFC"
cf_case g2; gq -C "$CFD/origin.git" update-ref refs/pull/1/head "$(git -C "$CFD/wt" rev-parse HEAD)"
gq -C "$CFD/main" config --add remote.origin.fetch '+refs/pull/*:refs/remotes/origin/pr/*'; gq -C "$CFD/main" fetch -q origin
printf '[branch "g2"]\n\tremote = origin\n\tmerge = refs/pull/1/head\n' >>"$CFC"
cf_case x1; gq -C "$CFD/main" config remote.origin.fetch '+refs/heads/*:refs/remotes/mirror/*'; gq -C "$CFD/main" fetch -q origin
for cf_r in $(git -C "$CFD/main" for-each-ref --format='%(refname)' refs/remotes/origin); do gq -C "$CFD/main" update-ref -d "$cf_r"; done
printf '[branch "x1"]\n\tremote = origin\n\tmerge = refs/heads/x1\n' >>"$CFC"
cf_sec x2 '\tremote = upstream\n\tmerge = refs/heads/x2\n'
cf_sec p1 '\tremote = origin\n\tpushRemote = fork\n\tmerge = refs/heads/p1\n[remote]\n\tpushDefault = fork\n'

echo "-- per-worktree config, include and includeIf"
cf_case wt1; gq -C "$CFD/main" config extensions.worktreeConfig true
printf '[branch "wt1"]\n\tremote = origin\n\tmerge = refs/heads/wt1\n' >>"$CFD/main/.git/worktrees/wt/config.worktree"
cf_sec wt2 '\tremote = nothere\n\tmerge = refs/heads/wt2\n'; gq -C "$CFD/main" config extensions.worktreeConfig true
printf '[branch "wt2"]\n\tremote = origin\n' >>"$CFD/main/.git/worktrees/wt/config.worktree"
cf_case i1; printf '[include]\n\tpath = up.inc\n' >>"$CFC"; printf '[branch "i1"]\n\tremote = origin\n\tmerge = refs/heads/i1\n' >"$CFD/main/.git/up.inc"
cf_case i2; printf '[include]\n\tpath = %s/up.inc\n' "$CFD" >>"$CFC"; printf '[branch "i2"]\n\tremote = origin\n\tmerge = refs/heads/i2\n' >"$CFD/up.inc"
cf_sec i3 '\tremote = origin\n\tmerge = refs/heads/i3\n[include]\n\tpath = no-such.inc\n'
cf_case i4; printf '[includeIf "gitdir:**/i4/**"]\n\tpath = up.inc\n' >>"$CFC"; printf '[branch "i4"]\n\tremote = origin\n\tmerge = refs/heads/i4\n' >"$CFD/main/.git/up.inc"
cf_sec i5 '\tremote = nothere\n\tmerge = refs/heads/i5\n[include]\n\tpath = up.inc\n'; printf '[branch "i5"]\n\tremote = origin\n' >"$CFD/main/.git/up.inc"
cf_sec i6 '\tremote = nothere\n\tmerge = refs/heads/i6\n[includeIf "gitdir:**/i6/**"]\n\tpath = up.inc\n'; printf '[branch "i6"]\n\tremote = origin\n' >"$CFD/main/.git/up.inc"
cf_sec i7 '\tremote = origin\n\tmerge = refs/heads/i7\n[include]\n\tpath = config\n'

echo "-- a line git cannot parse inside the branch's section"
cf_sec u1 '\tremote = origin\n\tmerge: refs/heads/u1\n'
cf_sec u2 '\tremote = origin\n\tmerge = "refs/heads/u2\n'

GO=$("$GT" keeps "$CFR")
# cf_row <id> <branch> <git's answer> <MinMacs's answer>. git's answer is for-each-ref's %(upstream:short) and
# %(upstream:track), or "fatal" when git refuses the config. MinMacs's is upstream|upstreamGone|upstreamUnknown|smart.
cf_row() {
  cf_w="$CFR/$1/wt"
  cf_git=$(git -C "$cf_w" for-each-ref --format='%(upstream:short)|%(upstream:track)' "refs/heads/$2" 2>/dev/null) || cf_git=fatal
  cf_git=$(printf '%s' "$cf_git" | tr '\t\n' '~~')   # a tab or a newline git reads into a name shows as ~
  cf_rp=$(git -C "$cf_w" rev-parse --abbrev-ref "$2@{upstream}" 2>/dev/null) || cf_rp=none
  cf_cm=$(git -C "$cf_w" config --get "branch.$2.merge" 2>/dev/null) || cf_cm=-
  cf_cr=$(git -C "$cf_w" config --get "branch.$2.remote" 2>/dev/null) || cf_cr=-
  cf_mm=$(printf '%s' "$GO" | python3 -c "
import json,sys; j=json.load(sys.stdin)['facts']; k=sys.argv[1]
v=j.get(k) or j.get(k[len('/private'):]) or {}
s=v.get('smart', '?'); s=s if s == 'delete now' else 'keep: ' + s
print('%s|%s|%s|%s' % (v.get('upstream'), v.get('upstreamGone'), v.get('upstreamUnknown'), s))" "$cf_w")
  printf '  row   %-4s git %-24s rev-parse %-18s config %s / %s\n        %-4s mm  %s\n' "$1" "$cf_git" "$cf_rp" "$cf_cr" "$cf_cm" "" "$cf_mm" | tr '\t\n' '~\n'
  check "config $1: git answers" "$3" "$cf_git"
  check "config $1: MinMacs reads what git reads" "$4" "$cf_mm"
  case "$cf_mm|$cf_git" in *"delete now|"*"[gone]") ;; *"delete now|"*) cf_lost="$cf_lost $1" ;; esac
}
cf_lost=""

echo "-- what git answers and what MinMacs reads, row by row"
# What MinMacs may say: the upstream git names, live or gone as git says; none where git has none; or not known, which
# keeps, where git refuses the config or this reader does not follow what it holds. Never gone where git has a live one.
cf_live() { echo "$1|False|False|keep: its branch is not merged and its remote branch still exists"; }
cf_none="None|False|False|keep: its branch is not merged and it tracks no remote branch"
cf_unread="None|False|True|keep: its branch is not merged and its remote branch could not be read"
cf_refused="None|False|True|keep: cannot verify what git holds of it"   # git refuses the config, so git status fails too
cf_row c1 c1 "origin/c1|" "$(cf_live origin/c1)"
cf_row c2 c2 "origin/c2|" "$(cf_live origin/c2)"
cf_row c3 c3 "origin/c3|" "$(cf_live origin/c3)"
cf_row c4 c4 "origin/c4|" "$(cf_live origin/c4)"
cf_row c5 c5 "origin/c5|" "$(cf_live origin/c5)"
cf_row c6 c6 "origin/c6|" "$(cf_live origin/c6)"
cf_row q1 q1 "origin/q1|" "$(cf_live origin/q1)"
cf_row q2 'q#2' "origin/q#2|" "$(cf_live 'origin/q#2')"
cf_row q3 'q;3' "origin/q;3|" "$(cf_live 'origin/q;3')"
cf_row q4 'q#4' "origin/q#4|" "$(cf_live 'origin/q#4')"
cf_row e1 'e"1' 'origin/e"1|' "$(cf_live 'origin/e"1')"
cf_row e2 e2 fatal "$cf_refused"
cf_row e3 e3 "origin/e3|[gone]" "$cf_unread"
cf_row e4 e4 'origin/e4\|[gone]' "$cf_unread"
cf_row e5 e5 "origin/e5|[gone]" "$cf_unread"
cf_row w1 w1 "origin/w1|" "$(cf_live origin/w1)"
cf_row w2 w2 "origin/w2|" "$(cf_live origin/w2)"
cf_row w3 w3 "|" "$cf_none"
cf_row k1 k1 "origin/k1|" "$(cf_live origin/k1)"
cf_row k2 k2 "origin/k2|" "$(cf_live origin/k2)"
cf_row s1 s1 "origin/s1|" "$(cf_live origin/s1)"
cf_row v1 v1 fatal "$cf_refused"
cf_row v2 v2 "|" "$cf_none"
cf_row h1 h1 "origin/h1|" "$(cf_live origin/h1)"
cf_row h2 h2 "|" "$cf_none"
cf_row h3 h3 "origin/h3|" "$(cf_live origin/h3)"
cf_row h4 Up4 "|" "$cf_none"
cf_row h5 h5 "origin/h5|" "$(cf_live origin/h5)"
cf_row h6 h6 "origin/h6|" "$(cf_live origin/h6)"
cf_row h7 h7 "origin/h7|" "$(cf_live origin/h7)"
cf_row h8 h8 "origin/h8|" "$(cf_live origin/h8)"
cf_row h9 h9 fatal "$cf_refused"
cf_row h10 h10 fatal "$cf_refused"
# git's @{upstream} is the FIRST merge line, though git config --get gives the last: d1's is gone, by git's own answer.
cf_row d1 d1 "origin/nothere|[gone]" "origin/nothere|True|False|delete now"
cf_row d2 d2 "origin/d2|" "$(cf_live origin/d2)"
cf_row d3 d3 "origin/d3|" "$(cf_live origin/d3)"
cf_row d4 d4 "|" "$cf_none"
cf_row d5 d5 "origin/d5|" "$(cf_live origin/d5)"
cf_row r1 r1 "origin/r1|" "$(cf_live origin/r1)"
cf_row l1 l1 "main|[ahead 1]" "$(cf_live main)"
cf_row l2 l2 "main|[ahead 1]" "$cf_unread"
cf_row g1 g1 "|" "$cf_none"
cf_row g2 g2 "origin/pr/1/head|" "$(cf_live origin/pr/1/head)"
cf_row x1 x1 "mirror/x1|" "$(cf_live mirror/x1)"
cf_row x2 x2 "|" "$cf_none"
cf_row p1 p1 "origin/p1|" "$(cf_live origin/p1)"
cf_row wt1 wt1 "origin/wt1|" "$(cf_live origin/wt1)"
cf_row wt2 wt2 "origin/wt2|" "$(cf_live origin/wt2)"
cf_row i1 i1 "origin/i1|" "$(cf_live origin/i1)"
cf_row i2 i2 "origin/i2|" "$(cf_live origin/i2)"
cf_row i3 i3 "origin/i3|" "$(cf_live origin/i3)"
cf_row i4 i4 "origin/i4|" "$cf_unread"
cf_row i5 i5 "origin/i5|" "$(cf_live origin/i5)"
cf_row i6 i6 "origin/i6|" "$cf_unread"
cf_row i7 i7 fatal "$cf_refused"
cf_row u1 u1 fatal "$cf_refused"
cf_row u2 u2 fatal "$cf_refused"
check "config: Smart deletes no worktree whose upstream git says is live, or that git has none of" "" "$cf_lost"
