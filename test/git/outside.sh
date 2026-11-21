# Issue #120: the config git reads outside the repo, the system, XDG and global files and the environment. Sourced by
# test/git.sh after config.sh, with gq, gc, check and the tool $GT. One repo per row, as config.sh makes them, whose own
# config names origin/<id>, a remote branch that is deleted, its commit kept on two other remote refs:
# refs/remotes/origin/kept-<id> and refs/remotes/elsewhere/<id>. So by the repo's own config the remote branch is gone,
# and Smart deletes the worktree. Each row puts one spelling into a file outside the repo, or the environment, and
# asks git and MinMacs under that row's environment alone: a fake HOME, and GIT_CONFIG_SYSTEM and GIT_CONFIG_GLOBAL
# named, the same for both. Nothing reads the real ~/.gitconfig or /etc/gitconfig of the Mac it runs on.
# Every fixture lies in $MINMACS_HOME/git/outside.

OD="$G/outside"; ODR="$OD/roots"; mkdir -p "$ODR"; : >"$OD/empty"
# The fixtures are made with no config from outside, as config.sh makes them.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS XDG_CONFIG_HOME
# What makes the branch's upstream live for git when it comes first: origin's heads mapped to elsewhere/*.
od_live='[remote "origin"]\n\tfetch = +refs/heads/*:refs/remotes/elsewhere/*\n'

# od_case <id>: the row's repo. ODD is its folder, ODF the folder of its outside files, ODH its fake home.
od_case() {
  ODD="$ODR/$1"; ODF="$OD/files/$1"; ODH="$ODF/home"; mkdir -p "$ODD" "$ODH"
  gq init -q --bare "$ODD/origin.git"; gq clone -q "$ODD/origin.git" "$ODD/main"
  gc "$ODD/main" base.txt base base; gq -C "$ODD/main" push -q -u origin main; gq -C "$ODD/main" remote set-head origin main
  gq -C "$ODD/main" worktree add -q -b "$1" "$ODD/wt" main
  gc "$ODD/wt" open.txt open open
  gq -C "$ODD/wt" push -q -u origin "$1"
  od_tip=$(git -C "$ODD/wt" rev-parse HEAD)
  gq -C "$ODD/main" update-ref "refs/remotes/origin/kept-$1" "$od_tip"
  gq -C "$ODD/main" update-ref "refs/remotes/elsewhere/$1" "$od_tip"
  gq -C "$ODD/main" update-ref -d "refs/remotes/origin/$1"
}
# od_put <file> <body as printf takes it>
od_put() { mkdir -p "$(dirname "$1")"; printf "$2" >"$1"; }

od_case o0
od_case g1; od_put "$ODF/global" "$od_live"
od_case g2; od_put "$ODF/global" '[branch "g2"]\n\tmerge = refs/heads/main\n'
od_case g3; od_put "$ODF/global" '[branch "g3"]\n\tremote = elsewhere\n'
od_case g4; od_put "$ODF/global" '[include]\n\tpath = live.inc\n'; od_put "$ODF/live.inc" "$od_live"
od_case g5; od_put "$ODF/global" "[includeIf \"gitdir:$ODR/\"]\n\tpath = live.inc\n"; od_put "$ODF/live.inc" "$od_live"
od_case g6; od_put "$ODF/global" '[includeIf "onbranch:nomatch"]\n\tpath = live.inc\n'; od_put "$ODF/live.inc" "$od_live"
# The usual global file: who you are, an includeIf for another email, the pull-request tip of another remote, and
# keys for other branches or that no upstream is made of.
od_case g7; od_put "$ODF/global" "[user]\n\tname = fixture\n\temail = fixture@example.invalid\n[includeIf \"gitdir:$ODR/\"]\n\tpath = work.inc\n[includeIf \"gitdir:/nowhere/\"]\n\tpath = other.inc\n[remote \"upstream\"]\n\tfetch = +refs/pull/*/head:refs/remotes/upstream/pr/*\n[pull]\n\trebase = true\n[init]\n\tdefaultBranch = main\n[url \"git@example.invalid:\"]\n\tinsteadOf = https://example.invalid/\n[branch \"g7\"]\n\tdescription = a note\n[branch \"other\"]\n\tremote = origin\n\tmerge = refs/heads/other\n"
od_put "$ODF/work.inc" '[user]\n\temail = work@example.invalid\n'
od_case g8; od_put "$ODF/global" '[remote "origin"]\n\tfetch = +refs/pull/*/head:refs/remotes/origin/pr/*\n'
od_case g9; od_put "$ODF/global" '[remote "origin"]\n\turl = /nowhere\n'
od_case g10; od_put "$ODF/global" '[branch "x"\n'
od_case g11; od_put "$ODF/global" '[url "https://example.invalid/"]\n\tinsteadOf\n'
od_case g12; od_put "$ODF/global" '[extensions]\n\tworktreeConfig = true\n'
od_put "$ODD/main/.git/worktrees/wt/config.worktree" '[branch "g12"]\n\tmerge = refs/heads/main\n'
od_case g13; od_put "$ODF/global" "$od_live"; chmod 000 "$ODF/global"
od_case g14; od_put "$ODF/global" "[includeIf \"gitdir:$ODR/\"]\n\tpath = no-such.inc\n"
od_case g15; od_put "$ODF/global" '[include]\n\tpath = /dev/null\n'
od_case g16; od_put "$ODF/global" '[remote "origin"]\n\tfetch = ^refs/heads/g16\n'
od_case s1; od_put "$ODF/system" "$od_live"
od_case s2; od_put "$ODF/system" "$od_live"
od_case x1; od_put "$ODF/xdg/git/config" "$od_live"
od_case x2; od_put "$ODH/.config/git/config" "$od_live"
od_case h1; od_put "$ODH/.gitconfig" "$od_live"
od_case h2; od_put "$ODH/.gitconfig" "$od_live"
od_case h3; od_put "$ODH/.gitconfig" "$od_live"
od_case h4; od_put "$ODH/.gitconfig" '[include]\n\tpath = ~/live.inc\n'; od_put "$ODH/live.inc" "$od_live"
# The environment is read after the repo's config, so its remote wins: the repo has a remote elsewhere of its own.
for od_e in e1 e2; do
  od_case $od_e; gq -C "$ODD/main" config remote.elsewhere.url "$ODD/origin.git"
  gq -C "$ODD/main" config remote.elsewhere.fetch '+refs/heads/*:refs/remotes/elsewhere/*'
done

# od_row <id> <git's answer> <MinMacs's answer> <global file, or - for none named> [VAR=value ...]: git and the tool
# under the same environment: HOME the row's fake home, GIT_CONFIG_SYSTEM the empty file unless the row names one,
# and nothing else from outside. git's answer is for-each-ref's %(upstream:short)|%(upstream:track), or fatal.
# MinMacs's is upstream|upstreamGone|upstreamUnknown|smart.
od_row() {
  od_id=$1; od_gw=$2; od_mw=$3; od_gl=$4; shift 4
  od_w="$ODR/$od_id/wt"
  set -- HOME="$OD/files/$od_id/home" GIT_CONFIG_SYSTEM="$OD/empty" "$@"
  [ "$od_gl" = - ] || set -- GIT_CONFIG_GLOBAL="$od_gl" "$@"
  od_git=$(env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
    -u XDG_CONFIG_HOME "$@" git -C "$od_w" for-each-ref --format='%(upstream:short)|%(upstream:track)' "refs/heads/$od_id" 2>/dev/null) || od_git=fatal
  od_out=$(env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
    -u XDG_CONFIG_HOME "$@" "$GT" keeps "$ODR/$od_id")
  od_mm=$(printf '%s' "$od_out" | python3 -c "
import json,sys; j=json.load(sys.stdin)['facts']; k=sys.argv[1]
v=j.get(k) or j.get(k[len('/private'):]) or {}
s=v.get('smart', '?'); s=s if s == 'delete now' else 'keep: ' + s
print('%s|%s|%s|%s' % (v.get('upstream'), v.get('upstreamGone'), v.get('upstreamUnknown'), s))" "$od_w")
  printf '  row   %-4s git %-26s mm %s\n' "$od_id" "$od_git" "$od_mm"
  case " or $od_gw or " in *" or $od_git or "*) od_gw=$od_git ;; esac   # "a or b": either answer of git's
  check "outside $od_id: git answers" "$od_gw" "$od_git"
  check "outside $od_id: MinMacs reads what it may" "$od_mw" "$od_mm"
  case "$od_mm|$od_git" in *"delete now|"*"[gone]") ;; *"delete now|"*) od_lost="$od_lost $od_id" ;; esac
}
od_lost=""
od_gone() { echo "origin/$1|True|False|delete now"; }
od_unread="None|False|True|keep: its branch is not merged and its remote branch could not be read"

echo "-- config git reads outside the repo, row by row"
# MinMacs may say gone only where git says gone. Where a file outside the repo, or the environment, holds what can
# change this branch's upstream, the upstream is not known, which keeps. What cannot change it changes nothing.
od_row o0 "origin/o0|[gone]" "$(od_gone o0)" "$OD/empty"
od_row g1 "elsewhere/g1|" "$od_unread" "$OD/files/g1/global"                # the global file comes before the repo's
od_row g2 "origin/main|[ahead 1]" "$od_unread" "$OD/files/g2/global"        # the first merge is the upstream
od_row g3 "origin/g3|[gone]" "$od_unread" "$OD/files/g3/global"             # the last remote, the repo's, wins
od_row g4 "elsewhere/g4|" "$od_unread" "$OD/files/g4/global"
od_row g5 "elsewhere/g5|" "$od_unread" "$OD/files/g5/global"                # its condition holds
od_row g6 "origin/g6|[gone]" "$od_unread" "$OD/files/g6/global"             # its condition is not read here
od_row g7 "origin/g7|[gone]" "$(od_gone g7)" "$OD/files/g7/global"
od_row g8 "origin/g8|[gone]" "$(od_gone g8)" "$OD/files/g8/global"         # another remote's line, maps no head
od_row g9 "origin/g9|[gone]" "$od_unread" "$OD/files/g9/global"
od_row g10 fatal "None|False|True|keep: cannot verify what git holds of it" "$OD/files/g10/global"   # git status fails too
od_row g11 fatal "$od_unread" "$OD/files/g11/global"
od_row g12 "origin/g12|[gone]" "$od_unread" "$OD/files/g12/global"         # git reads extensions from the repo alone
# git skips a global file it may not read; root may read it.
od_row g13 "origin/g13|[gone] or elsewhere/g13|" "$od_unread" "$OD/files/g13/global"
od_row g14 "origin/g14|[gone]" "$(od_gone g14)" "$OD/files/g14/global"     # an include that is not there is none
od_row g15 "origin/g15|[gone]" "$(od_gone g15)" "$OD/files/g15/global"
od_row g16 "origin/g16|[gone] or |" "$od_unread" "$OD/files/g16/global"   # git 2.39 maps past a negative line
od_row s1 "elsewhere/s1|" "$od_unread" "$OD/empty" GIT_CONFIG_SYSTEM="$OD/files/s1/system"
od_row s2 "origin/s2|[gone]" "$(od_gone s2)" "$OD/empty" GIT_CONFIG_SYSTEM="$OD/files/s2/system" GIT_CONFIG_NOSYSTEM=1
od_row x1 "elsewhere/x1|" "$od_unread" - XDG_CONFIG_HOME="$OD/files/x1/xdg"
od_row x2 "elsewhere/x2|" "$od_unread" -
od_row h1 "elsewhere/h1|" "$od_unread" -
od_row h2 "origin/h2|[gone]" "$(od_gone h2)" "$OD/empty"                    # a global file named: ~/.gitconfig is not read
od_row h3 "origin/h3|[gone]" "$(od_gone h3)" /dev/null                      # /dev/null reads as empty
od_row h4 "elsewhere/h4|" "$od_unread" -                                    # ~ in an include is the fake home
od_row e1 "elsewhere/e1|" "$od_unread" "$OD/empty" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=branch.e1.remote GIT_CONFIG_VALUE_0=elsewhere
od_row e2 "elsewhere/e2|" "$od_unread" "$OD/empty" "GIT_CONFIG_PARAMETERS='branch.e2.remote'='elsewhere'"
chmod 600 "$OD/files/g13/global"
check "outside: Smart deletes no worktree whose upstream git says is live, or that git refuses" "" "$od_lost"

echo "-- the fresh check before a removal reads config again"
# config rewritten in place with the same size, inode and mtime to the nanosecond: origin's heads now map to
# mirror/*, where the branch's commit is. A read that trusts the memo still says gone, and Smart deletes.
od_case st1; gq -C "$ODD/main" update-ref refs/remotes/mirror/st1 "$od_tip"
OT="$G/outsidetool"
clang -fobjc-arc -O1 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=14.0 -DMM_TESTS -ISources \
  $(find Sources/Core -name '*.m' | LC_ALL=C sort) test/git/outsidetool.m -framework Cocoa -framework IOKit \
  -framework UserNotifications -lsqlite3 -o "$OT" >"$G/outside-clang.log" 2>&1
check "outside: the tool builds" 0 "$?"
od_out=$(env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM HOME="$OD/files/st1/home" GIT_CONFIG_GLOBAL="$OD/empty" \
  GIT_CONFIG_SYSTEM="$OD/empty" "$OT" stale "$ODD/wt" "$ODD/main/.git/config" 'refs/remotes/origin/*' 'refs/remotes/mirror/*')
od_sv() { printf '%s' "$od_out" | json "j['$1']"; }
od_git=$(git -C "$ODD/wt" for-each-ref --format='%(upstream:short)|%(upstream:track)' refs/heads/st1)
printf '  row   st1  git %-26s before %s, after %s\n' "$od_git" "$(od_sv before)" "$(od_sv after)"
check "outside st1: the rewrite keeps size, inode and mtime" yes "$(od_sv sameStamp)"
check "outside st1: before it, gone" "origin/st1|True|False|delete now" "$(od_sv before)"
check "outside st1: git answers after it" "mirror/st1|" "$od_git"
check "outside st1: the fresh read after it says what git says" "mirror/st1|False|False|keep: its branch is not merged and its remote branch still exists" "$(od_sv after)"
