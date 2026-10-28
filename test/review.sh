# Issue #17: the review broker. Sourced by test.sh after core.
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

# Investigate has its own section, test/investigate.sh.

echo "  -- the wake queue"
"$RV" wake >"$rv_dir/wake.out" 2>&1
check "rv wake runs" 0 "$?"
while IFS="$rv_tab" read -r rv_n rv_w rv_g; do check "$rv_n" "$rv_w" "$rv_g"; done <"$rv_dir/wake.out"
check "no call folder is left behind" 0 "$(ls "$MINMACS_HOME/review/calls" 2>/dev/null | wc -l | tr -d ' ')"
