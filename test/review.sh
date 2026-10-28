# Issues #17, #32, #33, #34 and #36: the review broker. Sourced by test.sh after core.
# Builds test/review/rv.m with Sources/Core and runs it against the fake CLIs in test/review, ported from LocoHost.
# The real claude and codex are never run: MINMACS_CLAUDE and MINMACS_CODEX always name a fake or a path that fails.
# Every file the broker writes goes to $MINMACS_HOME/review, and every fixture lives in $MINMACS_HOME/rv.

rv_dir="$MINMACS_HOME/rv"
mkdir -p "$rv_dir"
RV="$rv_dir/rv"
# The flags of build.sh, for this machine's arch only. Every Core .m goes in, so the merged Store and Graph are used once they land.
if clang -fobjc-arc -O2 -Wall -mmacosx-version-min=14.0 -ISources \
     -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
     $(find Sources/Core -name '*.m' | LC_ALL=C sort) test/review/rv.m -o "$RV" >"$rv_dir/clang.log" 2>&1; then
  check "test/review/rv.m builds with no warnings" 0 "$(grep -c "warning:" "$rv_dir/clang.log")"
else
  check "test/review/rv.m builds" 0 1
  tail -20 "$rv_dir/clang.log"
fi

export MINMACS_CLAUDE="$ROOT/test/review/fakeclaude.py" MINMACS_CODEX="$ROOT/test/review/fakecodex.py"
export RV_TEST_SENT="$rv_dir/sent.json"
rv_app="$rv_dir/fixture-app"
mkdir -p "$rv_app"
printf 'API_TOKEN=ENVSECRET999\n' >"$rv_app/.env"
rv_fx() { rv_n=$1; shift; python3 -I test/review/fixture.py "$rv_dir/$rv_n.json" "$rv_n" "$@"; }   # expert folder [--move part]...
rv_fresh() { rm -f "$RV_TEST_SENT" "$RV_TEST_SENT".*; }
rv_get() { json "$1" <"$rv_dir/out.json"; }
rv_sent() { python3 -c "
import json, sys
calls = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
j = calls[-1]
items = [f for c in calls for b in c['blocks'] for f in b['f']]
print($1)" "$RV_TEST_SENT"; }

echo "  -- checks without a model"
"$RV" unit >"$rv_dir/unit.out" 2>&1
check "rv unit runs" 0 "$?"
rv_tab=$(printf '\t')
while IFS="$rv_tab" read -r rv_n rv_w rv_g; do check "$rv_n" "$rv_w" "$rv_g"; done <"$rv_dir/unit.out"

echo "  -- review with the fake CLI, LocoHost's checks"
rv_fx lh "$(cd "$rv_app" && pwd -P)" >/dev/null; rv_fresh
RV_TEST_GO="#dev" ANTHROPIC_API_KEY=sk-ant-test "$RV" review "$rv_dir/lh.json" >"$rv_dir/out.json"
check "review with the fake CLI succeeds, without the API key" 0 "$?"
grep -q "SUPERSECRET123" "$RV_TEST_SENT";                        check "the api key value is not sent" 1 "$?"
grep -q "hunter2" "$RV_TEST_SENT";                               check "the URL password is not sent" 1 "$?"
grep -q "http.server" "$RV_TEST_SENT";                           check "the rest of the command is sent" 0 "$?"
grep -q "fixture-app" "$RV_TEST_SENT";                           check "the package.json name is sent" 0 "$?"
grep -q "ENVSECRET999" "$RV_TEST_SENT";                          check ".env contents are never sent" 1 "$?"
grep -q "Fixture session" "$RV_TEST_SENT";                       check "the agent session title is sent" 0 "$?"
grep -q "HUNTER77" "$RV_TEST_SENT";                              check "a secret in the session prompt is redacted" 1 "$?"
grep -qF "$HOME/" "$RV_TEST_SENT";                               check "the home folder is never sent" 1 "$?"
grep -qF '"~/Documents/fixture-app"' "$RV_TEST_SENT";            check "a path in the home folder is sent as ~" 0 "$?"
check "null, false and zero facts are dropped" "[]" "$(rv_sent "sorted(k for f in items for k in f if k in ('locked', 'dirty', 'pr'))")"
check "one block per workstream, and one without an owner" 3 "$(rv_sent "len(j['blocks'])")"
check "the input is compact JSON with sorted keys" True \
  "$(python3 -c "import json,sys; l=open(sys.argv[1]).readline().strip(); print(l == json.dumps(json.loads(l), sort_keys=True, separators=(',', ':'), ensure_ascii=False))" "$RV_TEST_SENT")"
check "the facts come before now" True "$(python3 -c "import sys; l=open(sys.argv[1]).readline(); print(l.index('\"blocks\"') < l.index('\"now\"'))" "$RV_TEST_SENT")"
check "every finding gets a verdict" 5 "$(rv_get "len(j['verdicts'])")"
check "the verdict is in the expert's words" "idle go" "$(rv_get "' '.join(v['word'] + ' ' + v['kind'] for k, v in j['verdicts'].items() if k.endswith('#dev'))")"
check "and the others in its keep word" "in_use" "$(rv_get "sorted(set(v['word'] for k, v in j['verdicts'].items() if not k.endswith('#dev')))[0]")"
check "the review writes a summary, totals from code" "5 findings: 4 in use, 1 idle. Fixture summary: 5 items." "$(rv_get "j['summary']")"
check "one call for five findings" 1 "$(rv_get "len(j['calls'])")"
check "uncached is input, cache writes and output" 360 "$(rv_get "j['calls'][0]['uncached']")"
check "cache writes are split by TTL" "100 200 1000 30" "$(rv_get "' '.join(str(j['calls'][0][k]) for k in ('cache_write_5m', 'cache_write_1h', 'cache_read', 'thinking'))")"
check "the list cost is the CLI's" 0.0001 "$(rv_get "j['calls'][0]['list_cost_usd']")"
check "the budget counts the call" 360 "$(rv_get "j['uncached_today']")"
check "the call ran in its own folder" yes "$(python3 -c "import json,sys; c=json.loads(open(sys.argv[1]).readline()); print('yes' if '/review/calls/call.' in c['cwd'] else c['cwd'])" "$RV_TEST_SENT.calls")"
check "and the folder is gone after" no "$(python3 -c "import json,os,sys; c=json.loads(open(sys.argv[1]).readline()); print('yes' if os.path.exists(c['cwd']) else 'no')" "$RV_TEST_SENT.calls")"
check "the first review of the day asks a five minute cache" 5m "$(python3 -c "import json,sys; print(json.loads(open(sys.argv[1]).readline())['ttl'])" "$RV_TEST_SENT.calls")"
check "the review is saved, and lastFor reads it" True "$(rv_get "j['last_matches']")"

echo "  -- the fingerprint cache"
rv_fresh
"$RV" review "$rv_dir/lh.json" >"$rv_dir/out.json"
check "an unchanged finding is not sent again" 0 "$(rv_get "len(j['calls'])")"
check "and the CLI never ran" no "$([ -e "$RV_TEST_SENT.calls" ] && echo yes || echo no)"
check "its verdict is carried over in its own words" "idle 5" "$(rv_get "[v['word'] for k, v in j['verdicts'].items() if k.endswith('#dev')][0] + ' ' + str(j['decided'].get('cache'))")"
check "nothing moved, so the words of the summary stay" "5 findings: 4 in use, 1 idle. Fixture summary: 5 items." "$(rv_get "j['summary']")"
rv_fx lh "$(cd "$rv_app" && pwd -P)" --move "#api" >/dev/null; rv_fresh
"$RV" review "$rv_dir/lh.json" >"$rv_dir/out.json"
check "a moved fingerprint sends only that finding" "1 #api" "$(rv_sent "str(len(items)) + ' ' + items[0]['id'][-4:]")"
check "the next review within the hour asks a one hour cache" 1h "$(python3 -c "import json,sys; print(json.loads(open(sys.argv[1]).readline())['ttl'])" "$RV_TEST_SENT.calls")"
check "the history holds every review" 3 "$(rv_get "j['history']")"

echo "  -- the instance key and Core's context, issue #33"
rv_fx lh "$(cd "$rv_app" && pwd -P)" --move "#api" --restart "#api" >/dev/null; rv_fresh
"$RV" review "$rv_dir/lh.json" >"$rv_dir/out.json"
check "a new instance is sent again, though its fingerprint holds" "1 #api" "$(rv_sent "str(len(items)) + ' ' + items[0]['id'][-4:]")"
rv_fx lh "$(cd "$rv_app" && pwd -P)" --move "#api" --restart "#api" --head def >/dev/null; rv_fresh
"$RV" review "$rv_dir/lh.json" >"$rv_dir/out.json"
check "a new HEAD sends that workstream's findings again, and no other" "#api #dev" "$(rv_sent "' '.join(sorted(f['id'][-4:] for f in items))")"
check "each verdict keeps the context it was made for" True "$(rv_get "all(v['context'].startswith('gdef|') for k, v in j['verdicts'].items() if k.endswith(('#dev', '#api')))")"
"$RV" review "$rv_dir/lh.json" >"$rv_dir/out.json"
check "with nothing moved, the cache carries all five" 5 "$(rv_get "j['review_decided'].get('cache')")"

echo "  -- rules first: Core's work keeps and the triage count, issue #32"
rv_fx keeps "$rv_app" --keep "#web" >/dev/null; rv_fresh
"$RV" review "$rv_dir/keeps.json" >"$rv_dir/out.json"
check "a finding with a work keep is kept by Core's rule" "core.work-keeps in_use" "$(rv_get "' '.join([v['decided_by'] + ' ' + v['word'] for k, v in j['verdicts'].items() if k.endswith('#web')])")"
grep -q "#web" "$RV_TEST_SENT";                                  check "and never reaches the model" 1 "$?"
check "the review counts what decided each finding" "1 4 4" "$(rv_get "str(j['review_decided'].get('core.work-keeps')) + ' ' + str(j['review_decided'].get('model')) + ' ' + str(j['sent'])")"
"$RV" review "$rv_dir/keeps.json" >"$rv_dir/out.json"
check "a rule decides again on the next review, and is not carried" "1 4" "$(rv_get "str(j['review_decided'].get('core.work-keeps')) + ' ' + str(j['review_decided'].get('cache'))")"

echo "  -- one fact block per workstream, issue #34"
rv_fx blocks "$rv_app" >/dev/null; rv_fresh
"$RV" review "$rv_dir/blocks.json" --shared agent_session,branch >"$rv_dir/out.json"
rv_line() { python3 -c "
import json, sys
j = json.loads(open(sys.argv[1]).readline())
print($1)" "$RV_TEST_SENT"; }
check "a fact both servers of a workstream share is sent once, in ws" "{'branch': 'main'} 0" \
  "$(rv_line "[b.get('ws') for b in j['blocks'] if len(b['f']) == 2 and any('#dev' in f['id'] for f in b['f'])][0], sum('branch' in f for b in j['blocks'] for f in b['f'])")"
check "a shared key with different values stays with each finding" 1 "$(rv_line "sum('agent_session' in f for b in j['blocks'] for f in b['f'])")"
check "a fact every finding shares is sent once, in all" "{'quiet_after_minutes': 30} 0" \
  "$(rv_line "j.get('all'), sum('quiet_after_minutes' in f for b in j['blocks'] for f in b['f'])")"
check "only the block whose findings share a value gets ws" 1 "$(rv_line "sum('ws' in b for b in j['blocks'])")"
check "the model still reads every finding" 5 "$(rv_get "len(j['verdicts'])")"
check "the system prompt says how the blocks read" True "$(python3 -c "import json,sys; print(json.loads(open(sys.argv[1]).readline())['note'])" "$RV_TEST_SENT.calls")"

echo "  -- rules first"
rv_fx rules "$rv_app" >/dev/null; rv_fresh
"$RV" review "$rv_dir/rules.json" --rules >"$rv_dir/out.json"
check "a rule decides the service without the model" "test.service-keeps in_use" "$(rv_get "' '.join([v['decided_by'] + ' ' + v['word'] for k, v in j['verdicts'].items() if k.endswith('postgres')])")"
grep -q "service:postgres" "$RV_TEST_SENT";                      check "and it is not sent" 1 "$?"
check "the broker counts what each rule decides" "1 4" "$(rv_get "str(j['decided'].get('test.service-keeps')) + ' ' + str(j['decided'].get('model'))")"

echo "  -- batches in parallel"
rv_fx batch "$rv_app" >/dev/null; rv_fresh
"$RV" review "$rv_dir/batch.json" --batch 2 --parallel 3 >"$rv_dir/out.json"
check "three batches and one summary call" 4 "$(rv_get "len(j['calls'])")"
check "the summary call sees every finding as a line" "Fixture overall summary: 5 lines." "$(rv_get "j['summary'].split('. ', 1)[1]")"
check "every finding is covered" 5 "$(rv_get "len(j['verdicts'])")"
check "every call had its own folder" 4 "$(python3 -c "import json,sys; print(len(set(json.loads(l)['cwd'] for l in open(sys.argv[1]))))" "$RV_TEST_SENT.calls")"
check "a workstream's findings share a batch" True "$(python3 -c "
import json, sys
calls = [json.loads(l) for l in open(sys.argv[1])]
ws = [sorted(set(b.get('w', '') for b in c['blocks'])) for c in calls]
print(all(len(w) == 1 for w in ws))" "$RV_TEST_SENT")"

echo "  -- Luna when Haiku is out of usage"
rv_fx luna "$rv_app" >/dev/null; rv_fresh
RV_TEST_CLAUDE_LIMIT=1 OPENAI_API_KEY=sk-test "$RV" review "$rv_dir/luna.json" --model auto >"$rv_dir/out.json"
check "auto falls back to Luna, without the API key" gpt-6-luna "$(rv_get "j['calls'][-1]['model']")"
check "and notes why Haiku was skipped" True "$(rv_get "'usage limit' in j['note']")"
grep -q "SUPERSECRET123" "$RV_TEST_SENT";                        check "the api key value is not sent to Luna" 1 "$?"
check "codex counts cached input apart from input" "15 5 7 3 22" "$(rv_get "' '.join(str(j['calls'][-1][k]) for k in ('input', 'cache_read', 'output', 'thinking', 'uncached'))")"
rv_fx luna2 "$rv_app" >/dev/null
RV_TEST_CODEX_UNSUPPORTED=gpt-6-luna "$RV" review "$rv_dir/luna2.json" --model luna >"$rv_dir/out.json"
check "luna moves on from a model the account lacks" gpt-5.6-luna "$(rv_get "j['calls'][-1]['model']")"

echo "  -- the Eager judge"
rv_fx judge "$rv_app" --keep "#web" >/dev/null; rv_fresh
RV_TEST_GO="#dev" RV_TEST_UNSURE="#api,#docs" RV_TEST_KEEP="#api" "$RV" review "$rv_dir/judge.json" --model haiku --judge >"$rv_dir/out.json"
rv_judged() { python3 -c "
import json, sys
ids = sorted(f['id'].replace(':', '#').split('#')[-1] for l in open(sys.argv[1]) if l.strip() for b in json.loads(l)['blocks'] for f in b['f'])
print(' '.join(ids))" "$RV_TEST_SENT.judge"; }
check "the judge sees what the review keeps, not a sure go or a work keep" "api docs postgres" "$(rv_judged)"
check "the judge gets the first review" True "$(python3 -c "import json,sys; print(all('first' in f for b in json.loads(open(sys.argv[1]).readline())['blocks'] for f in b['f']))" "$RV_TEST_SENT.judge")"
check "the judge keeps a finding with evidence" "in_use True fixture: a test client still uses it" "$(rv_get "' '.join(str(v[k]) for k, v in [x for x in j['verdicts'].items() if x[0].endswith('#api')] for k in ('word', 'judged', 'keep_evidence'))")"
check "without evidence the judge says go" "idle judge" "$(rv_get "' '.join(v['word'] + ' ' + v['decided_by'] for k, v in j['verdicts'].items() if k.endswith('#docs'))")"
check "the broker counts what the judge decided" 3 "$(rv_get "j['decided'].get('judge')")"
rv_fx judgepar "$rv_app" --keep "#web" >/dev/null; rv_fresh
RV_TEST_GO="#dev" RV_TEST_UNSURE="#api,#docs" RV_TEST_KEEP="#api" "$RV" review "$rv_dir/judgepar.json" --model haiku --judge --batch 1 --parallel 3 >"$rv_dir/out.json"
check "the judge in parallel batches of one gives the same verdicts" "in_use idle 3" \
  "$(rv_get "' '.join([v['word'] for k, v in j['verdicts'].items() if k.endswith(e)][0] for e in ('#api', '#docs')) + ' ' + str(j['decided'].get('judge'))")"
rv_fx judgefail "$rv_app" >/dev/null; rv_fresh
RV_TEST_GO="#dev" RV_TEST_JUDGE_FAIL=1 "$RV" review "$rv_dir/judgefail.json" --model haiku --judge >"$rv_dir/out.json"
check "a failed judge is reported" True "$(rv_get "'the judge fails' in (j['judge_error'] or '')")"
check "and keeps every finding it was asked about" "in_use judge-failed 4" "$(rv_get "' '.join(sorted(set(v['word'] + ' ' + v['decided_by'] for k, v in j['verdicts'].items() if not k.endswith('#dev')))) + ' ' + str(sum(1 for v in j['verdicts'].values() if v['decided_by'] == 'judge-failed'))")"
rv_fresh
RV_TEST_GO="#dev" "$RV" review "$rv_dir/judgefail.json" --model haiku >"$rv_dir/out.json"
check "the next review asks the model again" 4 "$(rv_sent "len(items)")"

echo "  -- the daily budget"
rv_fx budget "$rv_app" >/dev/null; rv_fresh
"$RV" review "$rv_dir/budget.json" --trigger schedule --budget 100 >"$rv_dir/out.json"
check "a scheduled review waits when the day is over budget" 1 "$?"
check "and says so" True "$(rv_get "'budget' in j['error']")"
check "and asks no model" no "$([ -e "$RV_TEST_SENT.calls" ] && echo yes || echo no)"
"$RV" review "$rv_dir/budget.json" --trigger manual --budget 100 >"$rv_dir/out.json"
check "a manual review still runs" 0 "$?"

echo "  -- a failed review"
rv_fx fail "$rv_app" >/dev/null; rv_fresh
RV_TEST_CLAUDE_LIMIT=1 MINMACS_CODEX=/usr/bin/false "$RV" review "$rv_dir/fail.json" --model auto >"$rv_dir/out.json" 2>&1
check "both models failing exits 1" 1 "$?"
check "and leaves no verdict" 0 "$(rv_get "len(j['verdicts'])")"
MINMACS_CLAUDE=/usr/bin/false "$RV" review "$rv_dir/fail.json" --model haiku >"$rv_dir/out.json" 2>&1
check "review reports failure with exit 1" 1 "$?"
MINMACS_CLAUDE="$rv_dir/no-such-claude" "$RV" review "$rv_dir/fail.json" --model haiku >"$rv_dir/out.json" 2>&1
check "a missing CLI fails, and nothing else is tried" True "$(rv_get "j['error'].startswith('could not start no-such-claude')")"
"$RV" review "$rv_dir/fail.json" --model haiku >"$rv_dir/out.json"
check "a failed review is not carried over" 5 "$(rv_get "j['decided'].get('model')")"

echo "  -- Investigate"
rv_fresh
"$RV" investigate "$rv_app" "What is this folder for?" >"$rv_dir/out.json"
check "Investigate answers" 0 "$?"
check "it runs in the workstream's folder with only Read, Grep and Glob" "fixture-app Read,Grep,Glob" \
  "$(python3 -c "import json,os,sys; c=json.loads(open(sys.argv[1]).readline()); print(os.path.basename(c['cwd']), c['tools'])" "$RV_TEST_SENT.calls")"
check "and counts against the budget" "360 360" "$(rv_get "str(j['uncached']) + ' ' + str(j['investigate_today'])")"
"$RV" investigate "$rv_dir/no-such-folder" "Anything?" >"$rv_dir/out.json"
check "Investigate needs a folder" 1 "$?"

echo "  -- the wake queue"
"$RV" wake >"$rv_dir/wake.out" 2>&1
check "rv wake runs" 0 "$?"
while IFS="$rv_tab" read -r rv_n rv_w rv_g; do check "$rv_n" "$rv_w" "$rv_g"; done <"$rv_dir/wake.out"
check "no call folder is left behind" 0 "$(ls "$MINMACS_HOME/review/calls" 2>/dev/null | wc -l | tr -d ' ')"

echo "  -- tokens a day, issue #36"
# One generated day of findings for all five experts, replayed twice with the fake claude counting tokens from the
# bytes of each call: once as LocoHost 0.1 and WorkForest 0.1 asked, once through the broker. Each run has its own
# support folder. The real claude and codex never run: MINMACS_CLAUDE is the fake and codex is /usr/bin/false.
rd="$MINMACS_HOME/rvday"
mkdir -p "$rd"
RVD="$rd/rvday"
rd_src=$(find Sources -name '*.m' ! -path 'Sources/main.m' ! -path 'Sources/Shell/*' | LC_ALL=C sort)
# shellcheck disable=SC2086
if clang -fobjc-arc -O1 -Wall -mmacosx-version-min=14.0 -ISources \
     -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
     $rd_src test/review/day.m -o "$RVD" >"$rd/clang.log" 2>&1; then
  check "test/review/day.m builds with no warnings" 0 "$(grep -c "warning:" "$rd/clang.log")"
else
  check "test/review/day.m builds" 0 1
  tail -20 "$rd/clang.log"
fi
python3 -I test/review/dayfix.py "$rd/day.json"
check "the day fixture is the recorded one" e2d14c98d2ab33f7fd1736e146b66a5baecc8f6260c32f480039fbba7c5ac92f "$(shasum -a 256 "$rd/day.json" | cut -d' ' -f1)"
rd_run() {
  rd_m=$1; shift
  mkdir -p "$rd/$rd_m/claude" "$rd/$rd_m/codex"
  MINMACS_HOME="$rd/$rd_m" CLAUDE_CONFIG_DIR="$rd/$rd_m/claude" CODEX_HOME="$rd/$rd_m/codex" RV_TEST_SENT="$rd/$rd_m/sent.json" \
    RV_TEST_FACTS=1 RV_TEST_COUNT="$rd/$rd_m/count.json" MINMACS_CLAUDE="$ROOT/test/review/fakeclaude.py" MINMACS_CODEX=/usr/bin/false \
    "$RVD" "$@" 2>"$rd/$rd_m.err"
}
rd_run legacy legacy "$rd/day.json" test/review/legacy.json "$rd/legacy.json"; check "the 1.x replay runs" 0 "$?"
rd_run broker broker "$rd/day.json" "$rd/broker.json";                          check "the broker replay runs" 0 "$?"
rd_run fresh broker "$rd/day.json" "$rd/fresh.json" --fresh;                     check "the replay past the cache runs" 0 "$?"
check "no replay reports an error" 0 "$(cat "$rd"/*.err | wc -l | tr -d ' ')"
python3 -I test/review/daycompare.py "$rd/legacy.json" "$rd/broker.json" >"$rd/compare.json"
python3 -I test/review/daycompare.py "$rd/legacy.json" "$rd/fresh.json" >"$rd/compare-fresh.json"
rd_get() { json "$1" <"$rd/compare.json"; }
rd_run_get() { python3 -c "import json,sys; j=json.load(open(sys.argv[1])); print($2)" "$rd/$1.json"; }
check "every call went to the fake claude, and it counted each one" True "$(python3 -c "
import json, sys
ok = True
for m in ('legacy', 'broker'):
    calls = [json.loads(l) for l in open('$rd/%s/sent.json.calls' % m)]
    run = json.load(open('$rd/%s.json' % m))
    ok = ok and all(c['cli'] == 'claude' for c in calls) and len(calls) == sum(e['calls'] for e in run['experts'].values()) > 0
print(ok)")"
check "the 1.x replay asks at the 0.1 cadence" "24 12 0 0 0" \
  "$(rd_run_get legacy "' '.join(str(j['experts'][e]['reviews']) for e in ('locohost', 'workforest', 'minmacs', 'noonoo', 'insomnia'))")"
check "the broker reviews every expert every hour, and Insomnia asks for none" "24 24 24 24 0" \
  "$(rd_run_get broker "' '.join(str(j['experts'][e]['reviews']) for e in ('locohost', 'workforest', 'minmacs', 'noonoo', 'insomnia'))")"
check "rules decide every MinMacs and Noo-Noo finding" "0 0" \
  "$(rd_run_get broker "' '.join(str(j['experts'][e]['sent']) for e in ('minmacs', 'noonoo'))")"
check "no finding a rule or the cache decided reaches the model" True "$(python3 -c "
import json, sys
v = json.load(open('$rd/broker.json'))['verdicts']
sent = [json.loads(l) for l in open('$rd/broker/sent.json.ids')]
print(all(v['%d|%s' % ((c['clock'] - 60) // 3600, i)]['by'] == 'model' for c in sent for i in c['ids']) and len(sent) > 0)")"
check "a restarted server is asked again, not carried" model \
  "$(rd_run_get broker "[x['by'] for k, x in j['verdicts'].items() if k.startswith('10|') and k.endswith('#express')][0]")"
check "the day costs a fifth of the 1.x replay or less" True "$(rd_get "j['ratio'] <= 0.2")"
check "and a fifth of the 2.7M baseline or less" True "$(rd_get "j['after_uncached'] <= 540000")"
check "the broker never says go where the 1.x review did not" 0 \
  "$(rd_get "sum(n for k, n in j['differ_as'].items() if k.split(' to ')[1] in ('stale', 'idle'))")"
printf '  info  %s\n' "$(rd_get "'uncached tokens a day: %d in the 1.x replay, %d through the broker, %.1f %%; %d past the cache' % (j['before_uncached'], j['after_uncached'], 100 * j['ratio'], json.load(open('$rd/compare-fresh.json'))['after_uncached'])")"
printf '  info  %s\n' "$(rd_get "'as counted before, cache reads included: %d and %d. list cost: \$%.4f and \$%.4f' % (j['before_as_counted'], j['after_as_counted'], j['before_cost'], j['after_cost'])")"
printf '  info  %s\n' "$(rd_get "'findings reviewed: %d. rules %d, %.1f %%. cache %d, %.1f %%. model %d, %.1f %%' % (j['decided'], j['by_rules'], 100.0 * j['by_rules'] / j['decided'], j['by_cache'], 100.0 * j['by_cache'] / j['decided'], j['by_model'], 100.0 * j['by_model'] / j['decided'])")"
printf '  info  %s\n' "$(rd_get "'verdicts compared: %d, the same: %d, different: %d, %s' % (j['verdicts_compared'], j['verdicts_same'], j['verdicts_differ'], j['differ_as'])")"
printf '  info  %s\n' "$(python3 -I test/review/daybytes.py "$rd/legacy/sent.json" | json "'the 1.x inputs, %d calls: %d bytes pretty, %d compact, %d with empty values dropped, %d with shared values once' % (j['calls'], j['pretty'], j['compact'], j['dropped'], j['blocks'])")"
