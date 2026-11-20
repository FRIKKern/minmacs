# ===== A worktree whose size is not measured yet, in the verbs, issue #83 =====
# Sourced by test.sh after core. Fixtures only, all inside $MINMACS_HOME/unsized.<pid>: a repo with a bare origin, one
# worktree whose branch is merged with a Claude Code session that ran in it and ended two hours ago, and a session
# status file that names this shell's own pid in the main checkout, so that checkout is a workstream. No process
# starts. The built binary reads them cold, each time in a home of its own, so no walk of a worktree has ended and
# neither has a size. That 0 is no reading: `work wrap-up --dry-run` printed it as what the Wrap Up would free, and
# `work --json` gave it as a finding's diskFreed. Every run here is a dry run or a read, and nothing is removed.

un_dir="$(cd "$MINMACS_HOME" && pwd -P)/unsized.$$"
un_code="$un_dir/code"; un_tree="$un_code/shop.worktrees/feat"
mkdir -p "$un_code/shop.worktrees" "$un_dir/claude/projects" "$un_dir/codex" "$un_dir/root"
un_git() { git -c user.name=Fixture -c user.email=fixture@example.com -c commit.gpgsign=false -c init.defaultBranch=main "$@"; }
un_git init -q --bare "$un_dir/origin.git"
un_git clone -q "$un_dir/origin.git" "$un_code/shop" 2>/dev/null
( cd "$un_code/shop" && echo one >a.txt && un_git add -A && un_git commit -qm first && un_git push -q origin main 2>/dev/null )
un_git -C "$un_code/shop" worktree add -q -b feat "$un_tree" main 2>/dev/null
( cd "$un_tree" && echo two >b.txt && un_git add -A && un_git commit -qm "feat work" )
un_git -C "$un_code/shop" merge -q --ff-only feat && un_git -C "$un_code/shop" push -q origin main 2>/dev/null
un_s="$un_dir/claude/projects/$(printf %s "$un_tree" | tr '/.' '--')"; mkdir -p "$un_s"
python3 - "$un_s/unsized-$$.jsonl" "$un_tree" <<'PY'
import datetime, json, sys
t = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
with open(sys.argv[1], "w") as f:
    f.write(json.dumps({"type": "user", "timestamp": t, "cwd": sys.argv[2], "sessionId": "unsized-feat",
                        "message": {"role": "user", "content": "Finish the fixture work"}}) + "\n")
PY
mkdir -p "$un_dir/claude/sessions"
printf '{"pid":%s,"sessionId":"unsized-live-%s","cwd":"%s","startedAt":%s000,"kind":"interactive","status":"idle","statusUpdatedAt":%s000}\n' \
  "$$" "$$" "$un_code/shop" "$(date +%s)" "$(date +%s)" >"$un_dir/claude/sessions/$$.json"
# A new home for each read, named by the caller, so each one comes before the first walk of the worktree has ended.
un_cold() { # home words...
  un_home="$un_dir/home-$1"; shift; mkdir -p "$un_home"
  MINMACS_HOME="$un_home" MINMACS_ROOTS="$un_code" MINMACS_CLUTTER_ROOT="$un_dir/root" MINMACS_COLD=1 GIT_CONFIG_NOSYSTEM=1 \
    CLAUDE_CONFIG_DIR="$un_dir/claude" CODEX_HOME="$un_dir/codex" "$BIN" "$@" 2>/dev/null
}

echo "-- work wrap-up --dry-run"
un_json=$(un_cold json work wrap-up "$un_tree" --dry-run --json)
check "unsized: the dry run of a merged worktree whose session ended is ready" "True worktree" \
  "$(printf '%s' "$un_json" | json "'%s %s' % (j['ready'], ' '.join(p['step'] for p in j['parts']))")"
check "unsized: --json holds null for what it frees and marks it as no total, never 0" "None True" \
  "$(printf '%s' "$un_json" | json "'%s %s' % (j['freedBytes'], j.get('freedBytesPartial'))")"
un_text=$(un_cold text work wrap-up "$un_tree" --dry-run)
check "unsized: the dry run prints no size of 0 for a worktree not measured" "0 1" \
  "$(printf '%s\n' "$un_text" | grep -ciE 'free (zero|0)|[^0-9.](zero|0) ?(bytes|kb|mb|gb)') $(printf '%s\n' "$un_text" | grep -c '^Wrap Up feat would run 1 parts, disk back not measured yet:$')"
check "unsized: it still says what each part would do, and that nothing changed" "1 1 yes" \
  "$(printf '%s\n' "$un_text" | grep -c '^  worktree  Remove the worktree feat: would remove ') $(printf '%s\n' "$un_text" | grep -c '^Dry run. Nothing was changed.$') $([ -e "$un_tree/b.txt" ] && echo yes || echo no)"

echo "-- the findings of work --json"
un_f="' '.join('%s:%s:%s' % (f['title'], f['diskFreed'], f.get('measured')) for f in"
check "unsized: a finding's --json holds null and measured false for a worktree not measured, never 0" "shop:None:False" \
  "$(un_cold one work "$un_code/shop" --json | json "$un_f j['workstream']['findings'] if f['kind'] == 'worktree')")"
un_found=$(un_cold all work --json)
check "unsized: work --json gives the same among every workstream" "shop:None:False" \
  "$(printf '%s' "$un_found" | json "$un_f [f for w in j['workstreams'] for f in w['findings']] if f['kind'] == 'worktree')")"
check "unsized: every other finding keeps its number and says measured" 0 \
  "$(printf '%s' "$un_found" | json "sum(1 for w in j['workstreams'] for f in w['findings'] if f['kind'] != 'worktree' and (f['diskFreed'] is None or f.get('measured') is not True))")"

echo "-- the sources"
# The words for a size not measured are the menu window's own, MMWindowBackText, and no verb spells them again.
check "unsized: the words for a size not measured are the menu window's own" "0" \
  "$(grep -cE '@"[^"]*(measuring|so far|or more)' Sources/CLI/MMCoreVerbs.m Sources/CLI/MMGainsCLI.m Sources/Core/Act/MMWrapUp.m Sources/Core/Act/MMGainsAct.m Sources/Core/Store/MMGains.m Sources/Shell/MMFixRunner.m | awk -F: '{s+=$2} END {print s+0}')"

# ===== end of unsized =====
