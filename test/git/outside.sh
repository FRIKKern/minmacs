# Issue #120: the config git reads outside the repo, the system, XDG and global files and the environment. Sourced by
# test/git.sh after config.sh, with gq, gc, check and the tool $GT. One repo per row, as config.sh makes them, whose own
# config names origin/<id>, a remote branch that is deleted, its commit kept on two other remote refs:
# refs/remotes/origin/kept-<id> and refs/remotes/elsewhere/<id>. So by the repo's own config the remote branch is gone,
# and git is said to give the worktree back. Each row puts one spelling into a file outside the repo, or the environment, and
# asks git and MinMacs under that row's environment alone: a fake HOME, and GIT_CONFIG_SYSTEM and GIT_CONFIG_GLOBAL
# named, the same for both. Nothing reads the real ~/.gitconfig or /etc/gitconfig of the Mac it runs on.
# Every fixture lies in $MINMACS_HOME/git/outside.

OD="$G/outside"; ODR="$OD/roots"; mkdir -p "$ODR"; : >"$OD/empty"
# The fixtures are made with no config from outside, as config.sh makes them.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS XDG_CONFIG_HOME
# The system files of the gits MinMacs does not run, Apple's share/git-core/gitconfig and Homebrew's and MacPorts'
# etc/gitconfig, are read by the tool under this folder, which a row may fill, so it never reads the Mac's own. git
# itself still reads Apple's share/git-core/gitconfig, which no environment turns off but GIT_CONFIG_NOSYSTEM.
mkdir -p "$OD/root"; export MINMACS_TEST_GIT_ROOT="$OD/root"
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
# Issue #120's review, B1: a number past int range in a remote's bool. git refuses every read of the remotes over it,
# while git status, which reads no remote, passes. 2147483647 is the largest git takes.
od_case b1; od_put "$ODF/global" '[remote "x"]\n\tprune = 3000000000\n'
od_case b1s; od_put "$ODF/system" '[remote "x"]\n\tpruneTags = -2147483649\n'   # one past INT_MIN, refused by 2.39 and 2.50+
od_case b1k; od_put "$ODF/global" '[remote "x"]\n\tprune = 2147483647\n'
# B2: a line every git command refuses, in the XDG file, and in the system file of a git MinMacs does not run.
od_case b2; od_put "$ODF/xdg/git/config" '[user]\n\tname\n'
od_case b3; od_put "$ODF/root/opt/homebrew/etc/gitconfig" '[user]\n\tname\n'
od_case b4; od_put "$ODF/root/usr/local/etc/gitconfig" '[core]\n\tfilemode = maybe\n'
od_case b5; od_put "$ODF/root/opt/local/etc/gitconfig" "[includeIf \"hasconfig:remote.*.url:**\"]\n\tpath = $ODF/url.inc\n"
od_put "$ODF/url.inc" '[remote "other"]\n\turl = /nowhere\n'
od_case b6; od_put "$ODF/root/opt/homebrew/etc/gitconfig" '[credential]\n\thelper = osxkeychain\n'   # Homebrew's own
# The keys of a usual global file that every git command reads, in values git takes.
od_case b7; od_put "$ODF/global" '[core]\n\teditor = vim\n\tpager = less\n\tautocrlf = input\n\texcludesFile = ~/.gitignore\n\tquotePath = false\n\tabbrev = 12\n[user]\n\tname = fixture\n\temail = fixture@example.invalid\n\tuseConfigOnly = true\n[push]\n\tdefault = simple\n\tautoSetupRemote = true\n[branch]\n\tautoSetupMerge = always\n[color]\n\tui = auto\n[advice]\n\tstatusHints = false\n[credential]\n\thelper = osxkeychain\n[fetch]\n\tprune = true\n[pull]\n\trebase = true\n'
# Round 2, S4: everyday lines in the files MinMacs's own git reads, the global, ~/.gitconfig and XDG: keys git
# ignores or takes, some with no value. Where a line there made every command refuse, MinMacs's own git status would
# fail on it too, which keeps (b2, b12), so they are read as the repo's. In another git's file they still make it not
# known (b13): MinMacs's git status cannot be what fails there.
od_s4='[core]\n\tuntrackedCache = true\n\tlongpaths = true\n\tcheckStat = minimal\n\tabbrev = no\n\tignorecase = false\n\twhitespace = trailing-space\n\thooksPath = ~/.githooks\n\tpreloadIndex = true\n[branch]\n\tsort = -committerdate\n\tautoSetupRebase = always\n[push]\n\tuseForceIfIncludes = true\n\trecurseSubmodules = on-demand\n\tfollowTags = true\n\tdefault = current\n[fetch]\n\tprune\n\tpruneTags = true\n[pull]\n\trebase\n\tff = only\n[rerere]\n\tenabled\n\tautoUpdate = true\n[init]\n\tdefaultBranch = main\n[merge]\n\tconflictStyle = zdiff3\n\ttool = vimdiff\n[diff]\n\talgorithm = histogram\n\tcolorMoved = default\n\ttool = vimdiff\n[rebase]\n\tautoStash = true\n\tautoSquash = true\n\tupdateRefs = true\n[commit]\n\tverbose = true\n\tgpgsign = false\n[tag]\n\tsort = version:refname\n[column]\n\tui = auto\n[help]\n\tautocorrect = prompt\n[status]\n\tshowUntrackedFiles = all\n[gpg]\n\tformat = ssh\n[user]\n\tsigningkey = ~/.ssh/id.pub\n[color]\n\tdiff = auto\n[alias]\n\tst = status\n[gc]\n\tauto = 0\n'
od_case b11; od_put "$ODF/global" "$od_s4"
od_case b12; od_put "$ODF/global" '[core]\n\tfilemode = maybe\n'
od_case b13; od_put "$ODF/root/opt/homebrew/etc/gitconfig" '[core]\n\tuntrackedCache = true\n'
od_case b14; od_put "$ODH/.gitconfig" "$od_s4"
od_case b15; od_put "$ODF/xdg/git/config" "$od_s4"
# Issue #126: a line that a git later than MinMacs's own refuses in every command, while 2.39 ignores it, in a file
# MinMacs's own git reads. The person's shell may run the later git, so the upstream is not known. git v2.56.1:
od_case n1; od_put "$ODF/global" '[core]\n\tcommentString\n'           # environment.c:466, no value
od_case n1e; od_put "$ODF/global" '[core]\n\tcommentString = ""\n'     # environment.c:482, empty
od_case n2; od_put "$ODH/.gitconfig" '[core]\n\tlockFilePid = maybe\n' # environment.c:532, not a bool
od_case n3; od_put "$ODF/xdg/git/config" '[attr]\n\ttree\n'            # environment.c:678, no value
od_case n4; od_put "$ODF/global" '[index]\n\tmaxPathLen = junk\n'      # environment.c:743, not a number
od_case n4r; od_put "$ODF/global" '[index]\n\tmaxPathLen = 3g\n'       # environment.c:745, past INT_MAX
od_case n5; od_put "$ODF/global" '[core]\n\tcheckStat = Junk\n'        # environment.c:342
od_case n6; od_put "$ODF/global" '[advice]\n\tdiverging = maybe\n'     # advice.c:187, a key 2.39 does not have
# What both take: the values in another case, another attr key with no value, a unit.
od_case n7; od_put "$ODF/global" '[core]\n\tcheckStat = MINIMAL\n\tcommentString = //\n\tlockFilePid = 1\n[attr]\n\ttree = HEAD\n\tother\n[index]\n\tmaxPathLen = 4k\n[advice]\n\tdiverging = FALSE\n'
# Issue #126, part 4: Own()'s branch for Apple's git, the one the shipped app takes. A copy of the Command Line Tools
# git under a row's root reads the share file next to itself, as the real one reads its own. Skipped where there are
# no Command Line Tools, or where the copy does not read that file.
od_clt=/Library/Developer/CommandLineTools/usr/bin/git; od_cltok=""
od_share=usr/share/git-core/gitconfig
if [ -x "$od_clt" ]; then
  od_case a1; od_cp="$ODF/root/Library/Developer/CommandLineTools/usr/bin"; mkdir -p "$od_cp"; cp "$od_clt" "$od_cp/git"
  od_put "$ODF/root/Library/Developer/CommandLineTools/$od_share" '[marker]\n\tf = here\n'
  [ "$(cd / && env -i PATH=/usr/bin:/bin HOME="$ODH" GIT_CONFIG_SYSTEM="$OD/empty" GIT_CONFIG_GLOBAL="$OD/empty" \
    "$od_cp/git" config --show-origin --get marker.f 2>/dev/null)" = "file:$ODF/root/Library/Developer/CommandLineTools/$od_share	here" ] && od_cltok=yes
  # A line every command refuses: in the share file of the git in use, and in Xcode's, which that git does not read.
  od_put "$ODF/root/Library/Developer/CommandLineTools/$od_share" '[core]\n\tfilemode = maybe\n'
  od_case a2; mkdir -p "$ODF/root/Library/Developer/CommandLineTools/usr/bin"
  ln "$od_cp/git" "$ODF/root/Library/Developer/CommandLineTools/usr/bin/git" 2>/dev/null ||
    cp "$od_clt" "$ODF/root/Library/Developer/CommandLineTools/usr/bin/git"
  od_put "$ODF/root/Applications/Xcode.app/Contents/Developer/$od_share" '[core]\n\tfilemode = maybe\n'
fi
# S3: a global fetch line of origin that maps the merge to the very ref the repo's own line does.
od_case b8; od_put "$ODF/global" '[remote "origin"]\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n'
od_case b9; od_put "$ODF/global" '[remote "origin"]\n\tfetch = +refs/heads/b9:refs/remotes/origin/b9\n'
od_case b10; od_put "$ODF/global" '[remote "origin"]\n\tfetch = +refs/heads/b10:refs/remotes/elsewhere/b10\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n'
for od_e in e1 e2; do
  od_case $od_e; gq -C "$ODD/main" config remote.elsewhere.url "$ODD/origin.git"
  gq -C "$ODD/main" config remote.elsewhere.fetch '+refs/heads/*:refs/remotes/elsewhere/*'
done

# od_row <id> <git's answer> <MinMacs's answer> <global file, or - for none named> [VAR=value ...]: git and the tool
# under the same environment: HOME the row's fake home, GIT_CONFIG_SYSTEM the empty file unless the row names one,
# and nothing else from outside. git's answer is for-each-ref's %(upstream:short)|%(upstream:track), or fatal.
# MinMacs's is upstream|upstreamGone|upstreamUnknown|gitBack. A row about the system file of a git MinMacs does not run
# sets od_other to it: the tool finds it under its own MINMACS_TEST_GIT_ROOT, and git reads it as GIT_CONFIG_SYSTEM,
# as that git reads its own.
od_other=""
od_row() {
  od_id=$1; od_gw=$2; od_mw=$3; od_gl=$4; shift 4
  od_w="$ODR/$od_id/wt"
  set -- HOME="$OD/files/$od_id/home" GIT_CONFIG_SYSTEM="$OD/empty" "$@"
  [ "$od_gl" = - ] || set -- GIT_CONFIG_GLOBAL="$od_gl" "$@"
  od_git=$(env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
    -u XDG_CONFIG_HOME "$@" ${od_other:+GIT_CONFIG_SYSTEM="$OD/files/$od_id/root$od_other"} \
    git -C "$od_w" for-each-ref --format='%(upstream:short)|%(upstream:track)' "refs/heads/$od_id" 2>/dev/null) || od_git=fatal
  od_out=$(env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM -u GIT_CONFIG_NOSYSTEM -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
    -u XDG_CONFIG_HOME "$@" ${od_other:+MINMACS_TEST_GIT_ROOT="$OD/files/$od_id/root"} "$GT" keeps "$ODR/$od_id")
  od_mm=$(printf '%s' "$od_out" | python3 -c "
import json,sys; j=json.load(sys.stdin)['facts']; k=sys.argv[1]
v=j.get(k) or j.get(k[len('/private'):]) or {}
s=v.get('gitBack', '?'); s=s if s == 'git gives back' else 'keep: ' + s
print('%s|%s|%s|%s' % (v.get('upstream'), v.get('upstreamGone'), v.get('upstreamUnknown'), s))" "$od_w")
  printf '  row   %-4s git %-26s mm %s\n' "$od_id" "$od_git" "$od_mm"
  case " or $od_gw or " in *" or $od_git or "*) od_gw=$od_git ;; esac   # "a or b": either answer of git's
  case " or $od_mw or " in *" or $od_mm or "*) od_mw=$od_mm ;; esac    # and of MinMacs's
  check "outside $od_id: git answers" "$od_gw" "$od_git"
  check "outside $od_id: MinMacs reads what it may" "$od_mw" "$od_mm"
  case "$od_mm|$od_git" in *"git gives back|"*"[gone]") ;; *"git gives back|"*) od_lost="$od_lost $od_id" ;; esac
}
od_lost=""
od_gone() { echo "origin/$1|True|False|git gives back"; }
od_unread="None|False|True|keep: its branch is not merged and its remote branch could not be read"
# Not known either way: MinMacs's own git status passes, as 2.39 does, or fails, as a later git does.
od_unknown="$od_unread or None|False|True|keep: cannot verify what git holds of it"

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
od_row b1 fatal "$od_unread" "$OD/files/b1/global"
od_row b1s fatal "$od_unread" "$OD/empty" GIT_CONFIG_SYSTEM="$OD/files/b1s/system"
od_row b1k "origin/b1k|[gone]" "$(od_gone b1k)" "$OD/files/b1k/global"
od_row b2 fatal "origin/b2|True|False|keep: cannot verify what git holds of it" - XDG_CONFIG_HOME="$OD/files/b2/xdg"   # its git status fails
od_other=/opt/homebrew/etc/gitconfig; od_row b3 fatal "$od_unread" "$OD/empty"
od_other=/usr/local/etc/gitconfig; od_row b4 fatal "$od_unread" "$OD/empty"
od_other=/opt/local/etc/gitconfig; od_row b5 fatal "$od_unread" "$OD/empty"
od_other=/opt/homebrew/etc/gitconfig; od_row b6 "origin/b6|[gone]" "$(od_gone b6)" "$OD/empty"; od_other=""
od_row b7 "origin/b7|[gone]" "$(od_gone b7)" "$OD/files/b7/global"
od_row b8 "origin/b8|[gone]" "$(od_gone b8)" "$OD/files/b8/global"
od_row b9 "origin/b9|[gone]" "$(od_gone b9)" "$OD/files/b9/global"
od_row b10 "elsewhere/b10|" "$od_unread" "$OD/files/b10/global"           # the first line that maps it wins
od_row b11 "origin/b11|[gone]" "$(od_gone b11)" "$OD/files/b11/global"
od_row b12 fatal "origin/b12|True|False|keep: cannot verify what git holds of it" "$OD/files/b12/global"   # its git status fails
od_other=/opt/homebrew/etc/gitconfig; od_row b13 "origin/b13|[gone]" "$od_unread" "$OD/empty"; od_other=""
od_row b14 "origin/b14|[gone]" "$(od_gone b14)" -
od_row b15 "origin/b15|[gone]" "$(od_gone b15)" - XDG_CONFIG_HOME="$OD/files/b15/xdg"
# Issue #126: git 2.39 says gone, git 2.56 is fatal.
for od_n in n1 n1e n4 n4r n5 n6; do od_row $od_n "origin/$od_n|[gone] or fatal" "$od_unknown" "$OD/files/$od_n/global"; done
od_row n2 "origin/n2|[gone] or fatal" "$od_unknown" -
od_row n3 "origin/n3|[gone] or fatal" "$od_unknown" - XDG_CONFIG_HOME="$OD/files/n3/xdg"
od_row n7 "origin/n7|[gone]" "$(od_gone n7)" "$OD/files/n7/global"
if [ -n "$od_cltok" ]; then
  # MinMacs's git is the copy: its own share file is read as the repo's, and its status fails there, which keeps.
  od_other=/Library/Developer/CommandLineTools/$od_share
  od_row a1 fatal "origin/a1|True|False|keep: cannot verify what git holds of it" "$OD/empty" \
    MINMACS_GIT="$OD/files/a1/root/Library/Developer/CommandLineTools/usr/bin/git"
  od_other=/Applications/Xcode.app/Contents/Developer/$od_share
  od_row a2 fatal "$od_unread" "$OD/empty" MINMACS_GIT="$OD/files/a2/root/Library/Developer/CommandLineTools/usr/bin/git"
  od_other=""
else
  echo "  skip  a1 a2: no Command Line Tools git at $od_clt, or a copy of it does not read the share file beside it"
fi
od_row e1 "elsewhere/e1|" "$od_unread" "$OD/empty" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=branch.e1.remote GIT_CONFIG_VALUE_0=elsewhere
od_row e2 "elsewhere/e2|" "$od_unread" "$OD/empty" "GIT_CONFIG_PARAMETERS='branch.e2.remote'='elsewhere'"
chmod 600 "$OD/files/g13/global"
check "outside: git is never said to give back a worktree whose upstream git says is live, or that git refuses" "" "$od_lost"

echo "-- the fresh check before a removal reads config again"
# config rewritten in place with the same size, inode and mtime to the nanosecond: origin's heads now map to
# mirror/*, where the branch's commit is. A read that trusts the memo still says gone, and git is said to give it back.
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
check "outside st1: before it, gone" "origin/st1|True|False|git gives back" "$(od_sv before)"
check "outside st1: git answers after it" "mirror/st1|" "$od_git"
check "outside st1: the fresh read after it says what git says" "mirror/st1|False|False|keep: its branch is not merged and its remote branch still exists" "$(od_sv after)"

echo "-- a walk looks at the files outside the repo at most once a second, the fresh read always"
# The global file turns live: a walk's read may still say gone for up to a second, the fresh read never does.
od_case wd1; od_put "$ODF/global" '[remote "upstrm"]\n\tfetch = +refs/heads/*:refs/remotes/elsewhere/*\n'
od_out=$(env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM HOME="$ODH" GIT_CONFIG_GLOBAL="$ODF/global" \
  GIT_CONFIG_SYSTEM="$OD/empty" MINMACS_ROOTS="$ODD" "$OT" window "$ODD/wt" "$ODF/global" upstrm origin)
od_git=$(GIT_CONFIG_GLOBAL="$ODF/global" git -C "$ODD/wt" for-each-ref --format='%(upstream:short)|%(upstream:track)' refs/heads/wd1)
printf '  row   wd1  git %-26s walk at once %s\n' "$od_git" "$(od_sv walkNow)"
check "outside wd1: before it, gone" "$(od_gone wd1)" "$(od_sv before)"
check "outside wd1: git answers after it" "elsewhere/wd1|" "$od_git"
check "outside wd1: the fresh read right after it is not gone" "$od_unread" "$(od_sv fresh)"
check "outside wd1: a walk's read a second later is not gone" "$od_unread" "$(od_sv later)"

echo "-- the CLI's fresh check before a removal, as minmacs tidy runs it with no app"
# MMColdFacts's freshFactsFor:, the source MMRunAction checks a cold action on: the global file rewritten in place,
# with the same size, inode and mtime, right after the plan's read, so neither the second nor the memo may answer.
od_case cl1; od_put "$ODF/global" '[remote "upstrm"]\n\tfetch = +refs/heads/*:refs/remotes/elsewhere/*\n'
OC="$G/outsidecli"
# shellcheck disable=SC2046
clang -fobjc-arc -O1 -Wall -mmacosx-version-min=14.0 -DMM_TESTS -ISources \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
  $(find Sources -name '*.m' ! -path 'Sources/main.m' ! -path 'Sources/Shell/*' | LC_ALL=C sort) test/git/outsidecli.m \
  -o "$OC" >"$G/outsidecli-clang.log" 2>&1
check "outside: the CLI tool builds" 0 "$?"
od_out=$(env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM HOME="$ODH" GIT_CONFIG_GLOBAL="$ODF/global" \
  GIT_CONFIG_SYSTEM="$OD/empty" MINMACS_ROOTS="$ODD" "$OC" fresh "$ODD/wt" "$ODF/global" upstrm origin)
od_git=$(GIT_CONFIG_GLOBAL="$ODF/global" git -C "$ODD/wt" for-each-ref --format='%(upstream:short)|%(upstream:track)' refs/heads/cl1)
printf '  row   cl1  git %-26s plan %s, fresh %s\n' "$od_git" "$(od_sv plan)" "$(od_sv fresh)"
check "outside cl1: the rewrite keeps size, inode and mtime" yes "$(od_sv sameStamp)"
check "outside cl1: the plan's read, gone" "$(od_gone cl1)" "$(od_sv plan)"
check "outside cl1: git answers after it" "elsewhere/cl1|" "$od_git"
check "outside cl1: the CLI's fresh check is not gone" "$od_unread" "$(od_sv fresh)"
# Round 2, B4: an update pass that read the worktree before the change is still running, as one WaitForGit gave up on
# after 60 s, and writes the index after the fresh read. The fresh check hands over its own read, not the index's.
od_case cl2; od_put "$ODF/global" '[remote "upstrm"]\n\tfetch = +refs/heads/*:refs/remotes/elsewhere/*\n'
od_out=$(env -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM HOME="$ODH" GIT_CONFIG_GLOBAL="$ODF/global" \
  GIT_CONFIG_SYSTEM="$OD/empty" MINMACS_ROOTS="$ODD" "$OC" race "$ODD/wt" "$ODF/global" upstrm origin)
od_git=$(GIT_CONFIG_GLOBAL="$ODF/global" git -C "$ODD/wt" for-each-ref --format='%(upstream:short)|%(upstream:track)' refs/heads/cl2)
printf '  row   cl2  git %-26s plan %s, fresh %s, index %s\n' "$od_git" "$(od_sv plan)" "$(od_sv fresh)" "$(od_sv index)"
check "outside cl2: the plan's read, gone" "$(od_gone cl2)" "$(od_sv plan)"
check "outside cl2: git answers after it" "elsewhere/cl2|" "$od_git"
check "outside cl2: the held pass wrote its old read after the fresh one" "yes gone" "$(od_sv released) $(od_sv index)"
check "outside cl2: the CLI's fresh check is not gone" "$od_unread" "$(od_sv fresh)"
unset MINMACS_TEST_GIT_ROOT

echo "-- a build without MM_TESTS reads the real system files whatever MINMACS_TEST_GIT_ROOT says, issue #130"
# The probe prints Files and Own of MMGitOutside.m for the environment it is handed; the process's own is not read.
RP="$G/rootprobe"
clang -fobjc-arc -O1 -Wall -mmacosx-version-min=14.0 -ISources \
  $(find Sources/Core -name '*.m' ! -name MMGitOutside.m | LC_ALL=C sort) test/git/rootprobe.m -framework Cocoa -framework IOKit \
  -framework UserNotifications -lsqlite3 -o "$RP" >"$G/rootprobe-clang.log" 2>&1
check "outside: the probe builds without MM_TESTS" 0 "$?"
rp_plain=$("$RP" HOME="$OD/files/o0/home")
rp_root=$("$RP" HOME="$OD/files/o0/home" MINMACS_TEST_GIT_ROOT="$OD/root")
check "outside: with no MM_TESTS the system files are the Mac's own" 1 "$(printf '%s\n' "$rp_plain" | grep -c ' /etc/gitconfig$')"
check "outside: with no MM_TESTS, MINMACS_TEST_GIT_ROOT changes no file read" "$rp_plain" "$rp_root"
