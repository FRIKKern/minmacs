# Issue #35: Investigate, one deeper agent run on request for one finding or workstream. Sourced by test.sh after core.
# Builds test/investigate/inv.m with every .m under Sources but main.m, and runs it against test/investigate/fakeclaude.py,
# which starts MinMacs's own tool server the way Claude Code starts an MCP server, and makes scripted tool calls.
# The real claude is never run: MINMACS_CLAUDE always names the fake or a path that fails.
# Fixtures only, in a folder of their own inside $MINMACS_HOME: a project folder with a symlink and a symlinked folder
# that point out, a folder outside it with a secret, and a .env file. The only processes started are the fake claude
# and the tool server it starts, and each run waits for both to exit.

inv=$(cd "$MINMACS_HOME" && mkdir -p "inv-$$" && cd "inv-$$" && pwd -P)
inv_top="$MINMACS_HOME"
export MINMACS_HOME="$inv/home"     # a support folder of its own, so the estimate counts only these runs
mkdir -p "$MINMACS_HOME" "$inv/bin"
INV="$inv/bin/inv-$$"
inv_src=$(find Sources -name '*.m' ! -path 'Sources/main.m' | LC_ALL=C sort)
# shellcheck disable=SC2086
clang -fobjc-arc -O1 -Wall -mmacosx-version-min=14.0 -ISources -DMM_VERSION='"2.0.0"' \
  -framework Cocoa -framework IOKit -framework ServiceManagement -framework UserNotifications -framework QuartzCore -lsqlite3 \
  $inv_src test/investigate/inv.m -o "$INV" >"$inv/clang.log" 2>&1
check "test/investigate/inv.m builds" 0 "$?"
check "the Investigate sources have no warnings" 0 "$(grep -c 'warning:' "$inv/clang.log")"

fx="$inv/fx"
mkdir -p "$fx/in/src" "$fx/outside" "$fx/in-other"
printf '# Fixture app\nINSIDE_MARK readme\n' >"$fx/in/README.md"
printf 'const port = 3000;\nserve(port); // INSIDE_MARK\nexport {};\n' >"$fx/in/src/server.js"
printf 'notes INSIDE_MARK\n' >"$fx/in/notes.txt"
printf 'API_TOKEN=ENVSECRET777\n' >"$fx/in/.env"
printf 'OUTSIDE_SECRET_42\n' >"$fx/outside/secret.txt"
printf 'OTHER_SECRET_43\n' >"$fx/in-other/x.txt"
ln -s ../outside/secret.txt "$fx/in/link-out.txt"
ln -s ../outside "$fx/in/dir-out"
ln -s README.md "$fx/in/link-in.md"
ln -s in "$fx/in-link"
export INV_APP="$fx/in"
export MINMACS_CLAUDE="$ROOT/test/investigate/fakeclaude.py" MINMACS_CODEX=/usr/bin/false INV_TEST_SENT="$inv/sent"
unset INV_TEST_SCRIPT INV_TEST_FAIL INV_TEST_OUTPUT INV_TEST_SLEEP ANTHROPIC_API_KEY
inv_tab=$(printf '\t')
inv_fresh() { rm -f "$INV_TEST_SENT".*; }
inv_get() { json "$1" <"$inv/out.json"; }
inv_calls() { python3 -c "
import json, sys
c = [json.loads(l) for l in open(sys.argv[1]) if l.strip()][-1]
print($1)" "$INV_TEST_SENT.calls"; }
inv_tools() { python3 -c "
import json, sys
t = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
head, calls = t[0], t[1:]
print($1)" "$INV_TEST_SENT.tools"; }
inv_servers() { pgrep -f "_investigate-tools --folder $fx" | grep -c .; }

echo "  -- the path checks"
"$INV" unit "$fx" >"$inv/unit.out" 2>&1
check "inv unit runs" 0 "$?"
while IFS="$inv_tab" read -r n w g; do check "$n" "$w" "$g"; done <"$inv/unit.out"

echo "  -- a named pipe never holds the tool server"
# Read opens with O_NONBLOCK, so a FIFO inside the folder is refused as not a file, and the server answers at once.
# The pipe is made in its own fixture folder, so the scripted calls below see the same files as before.
mkdir -p "$fx/pipe-in"
mkfifo "$fx/pipe-in/inv-fifo-$$"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"Read","arguments":{"file_path":"inv-fifo-'"$$"'"}}}' \
  | "$INV" _investigate-tools --folder "$fx/pipe-in" >"$inv/fifo.out" 2>&1 &
inv_fifo_pid=$!
inv_fifo_wait=0
while kill -0 "$inv_fifo_pid" 2>/dev/null && [ "$inv_fifo_wait" -lt 50 ]; do sleep 0.1; inv_fifo_wait=$((inv_fifo_wait + 1)); done
inv_fifo_hung=no
if kill -0 "$inv_fifo_pid" 2>/dev/null; then inv_fifo_hung=yes; kill "$inv_fifo_pid" 2>/dev/null; fi
wait "$inv_fifo_pid" 2>/dev/null
check "Read of a named pipe does not hang the tool server" no "$inv_fifo_hung"
check "and is refused as not a file" 1 "$(grep -c 'is not a file inside the folders' "$inv/fifo.out")"
rm -f "$fx/pipe-in/inv-fifo-$$"

echo "  -- the cost before it runs"
inv_fresh
"$INV" investigate "$fx/in" "What is this folder for?" >"$inv/out.txt" 2>&1
check "investigate with no --yes succeeds" 0 "$?"
check "and asks no model" no "$([ -e "$INV_TEST_SENT.calls" ] && echo yes || echo no)"
check "it shows the estimate and the model" 1 "$(grep -c 'Cost      About 35,000 tokens on Haiku, an estimate before the first run.' "$inv/out.txt")"
check "it names the folder it may read" 1 "$(grep -c "Folders   $fx/in\$" "$inv/out.txt")"
check "and asks the person to confirm" 1 "$(grep -c 'Run it with --yes to confirm the cost.' "$inv/out.txt")"
"$INV" investigate "$fx/in" --yes --dry-run >/dev/null 2>&1
check "--dry-run with --yes asks no model either" no "$([ -e "$INV_TEST_SENT.calls" ] && echo yes || echo no)"
"$INV" investigate "$fx/in" --json >"$inv/out.json"
check "--json gives the estimate as numbers" "35000 0 haiku" "$(inv_get "' '.join(str(j['estimate'][k]) for k in ('tokens', 'based_on', 'model'))")"
"$INV" investigate "$inv/no-such-folder" >/dev/null 2>&1
check "a subject with no folder fails" 1 "$?"

echo "  -- one run through the fake CLI and the tool server"
cat >"$inv/script.json" <<JSON
[{"name": "Read", "arguments": {"file_path": "README.md"}},
 {"name": "Read", "arguments": {"file_path": "src/server.js", "offset": 2, "limit": 1}},
 {"name": "Read", "arguments": {"file_path": "$fx/outside/secret.txt"}},
 {"name": "Read", "arguments": {"file_path": "src/../../outside/secret.txt"}},
 {"name": "Read", "arguments": {"file_path": "link-out.txt"}},
 {"name": "Read", "arguments": {"file_path": "dir-out/secret.txt"}},
 {"name": "Read", "arguments": {"file_path": ".env"}},
 {"name": "Read", "arguments": {"file_path": "$fx/in-other/x.txt"}},
 {"name": "Grep", "arguments": {"pattern": "MARK|SECRET"}},
 {"name": "Grep", "arguments": {"pattern": "SECRET", "path": "dir-out"}},
 {"name": "Glob", "arguments": {"pattern": "**/*.txt"}},
 {"name": "Glob", "arguments": {"pattern": "../outside/*"}},
 {"name": "Glob", "arguments": {"pattern": "/etc/*"}},
 {"name": "Bash", "arguments": {"command": "cat $fx/outside/secret.txt"}},
 {"name": "Read", "arguments": {"file_path": "link-in.md"}}]
JSON
export INV_TEST_SCRIPT="$inv/script.json"
inv_fresh
ANTHROPIC_API_KEY=sk-ant-test "$INV" investigate "$fx/in" "What is this folder for?" --yes --json >"$inv/out.json" 2>"$inv/err.txt"
check "investigate --yes runs, without the API key" 0 "$?"
check "the built-in tools are off" "" "$(inv_calls "c['tools']")"
check "only MinMacs's Read, Grep and Glob are allowed" "mcp__minmacs__Read,mcp__minmacs__Grep,mcp__minmacs__Glob" "$(inv_calls "c['allowed']")"
check "only its own MCP config, and no settings files" "True ''" "$(inv_calls "str(c['strict']) + ' ' + repr(c['setting_sources'])")"
check "Haiku at low effort with a turn limit" "haiku low 12" "$(inv_calls "' '.join([c['model'], c['effort'], c['max_turns']])")"
check "a custom system prompt" True "$(inv_calls "c['system'].startswith('You look into one finding')")"
check "the call runs in a fresh folder, not the project" True "$(inv_calls "'/review/calls/' in c['cwd']")"
check "the prompt names the folders and the question" True "$(inv_calls "'Folders: $fx/in' in c['prompt'] and 'What is this folder for?' in c['prompt']")"
check "the tool server is MinMacs, with Read, Grep and Glob only" "minmacs Read,Grep,Glob" "$(inv_tools "head['server'] + ' ' + ','.join(head['tools'])")"
check "it answers an unknown method with an error" -32601 "$(inv_tools "head['unknown_method']")"
check "the refusals, call by call" "ok ok no no no no no no ok no ok no no no ok" "$(inv_tools "' '.join('no' if c['error'] else 'ok' for c in calls)")"
check "Read gives numbered lines" True "$(inv_tools "'     1\t# Fixture app' in calls[0]['text']")"
check "offset and limit pick the lines" "     2	serve(port); // INSIDE_MARK" "$(inv_tools "calls[1]['text'].strip(chr(10))")"
check "an absolute path outside is refused" True "$(inv_tools "'outside the folders' in calls[2]['text']")"
check ".. out of the folder is refused" True "$(inv_tools "'outside the folders' in calls[3]['text']")"
check "a symlink that points out is refused after realpath" True "$(inv_tools "'outside the folders' in calls[4]['text']")"
check "a symlinked folder that points out is refused" True "$(inv_tools "'outside the folders' in calls[5]['text']")"
check ".env is never read" True "$(inv_tools "'may hold secrets' in calls[6]['text']")"
check "a sibling folder with the same prefix is refused" True "$(inv_tools "'outside the folders' in calls[7]['text']")"
check "Grep finds the three files inside" 3 "$(inv_tools "calls[8]['text'].count('INSIDE_MARK')")"
check "Grep does not follow the symlinked folder or read .env" "False False" "$(inv_tools "str('OUTSIDE' in calls[8]['text']) + ' ' + str('ENVSECRET' in calls[8]['text'])")"
check "Grep with a path that points out is refused" True "$(inv_tools "calls[9]['error']")"
check "Glob lists the text files inside and no link" "notes.txt" "$(inv_tools "' '.join(sorted(l.rsplit('/', 1)[-1] for l in calls[10]['text'].split(chr(10)) if l))")"
check "a glob with .. is refused" True "$(inv_tools "'relative' in calls[11]['text']")"
check "an absolute glob is refused" True "$(inv_tools "'relative' in calls[12]['text']")"
check "any other tool is refused" True "$(inv_tools "'no tool named Bash' in calls[13]['text']")"
check "a symlink that stays inside is read" True "$(inv_tools "'INSIDE_MARK readme' in calls[14]['text']")"
grep -q "OUTSIDE_SECRET_42" "$INV_TEST_SENT.tools";       check "no byte of the file outside reaches the model" 1 "$?"
grep -q "OTHER_SECRET_43" "$INV_TEST_SENT.tools";         check "no byte of the sibling folder reaches the model" 1 "$?"
grep -q "ENVSECRET777" "$INV_TEST_SENT.tools";            check "no byte of .env reaches the model" 1 "$?"
check "the tool server exited with the call" 0 "$(inv_servers)"
check "the saved run counts the tool calls and the refusals" "15 10" "$(inv_get "str(j['tool_calls']) + ' ' + str(j['refused'])")"
check "the answer is saved, redacted" "True False" "$(inv_get "str('Fixture answer: 5 tool calls answered and 10 refused.' in j['answer']) + ' ' + str('FIXTURESECRET1' in j['answer'])")"
check "the usage is saved with it" "360 haiku" "$(inv_get "str(j['usage']['uncached']) + ' ' + j['model']")"
check "no audit file is left behind" 0 "$(ls "$MINMACS_HOME/review/investigate" 2>/dev/null | grep -c .)"

echo "  -- saved with the subject, and the estimate after"
"$INV" investigate "$fx/in" --json >"$inv/out.json"
check "a new process reads the saved answer" True "$(inv_get "j['last']['answer'].startswith('Fixture answer')")"
check "the estimate is the last run's cost" "360 1" "$(inv_get "str(j['estimate']['tokens']) + ' ' + str(j['estimate']['based_on'])")"
"$INV" investigate "$fx/in" >"$inv/out.txt"
check "the text shows the last answer" 1 "$(grep -c '^Last answer, just now:' "$inv/out.txt")"
check "and the new estimate" 1 "$(grep -c 'About 360 tokens on Haiku, the cost of the last run.' "$inv/out.txt")"
INV_TEST_OUTPUT=150 "$INV" investigate "$fx/in" --yes >/dev/null 2>&1
INV_TEST_OUTPUT=250 "$INV" investigate "$fx/in" --yes >"$inv/out.txt" 2>&1
check "a plain run prints the answer and its cost" 1 "$(grep -c '^Used 560 uncached tokens on haiku, with 15 tool calls, 10 refused.$' "$inv/out.txt")"
"$INV" investigate "$fx/in" --json >"$inv/out.json"
check "the estimate is the median of the runs" "460 3" "$(inv_get "str(j['estimate']['tokens']) + ' ' + str(j['estimate']['based_on'])")"

echo "  -- failures"
INV_TEST_FAIL=1 "$INV" investigate "$fx/in" --yes >"$inv/out.txt" 2>&1
check "a failed run exits 1" 1 "$?"
check "and says why" 1 "$(grep -c 'It failed: fixture: the run fails' "$inv/out.txt")"
"$INV" investigate "$fx/in" --json >"$inv/out.json"
check "the failure is saved with the subject" "fixture: the run fails" "$(inv_get "j['last']['error']")"
check "a failed run does not move the estimate" "460 3" "$(inv_get "str(j['estimate']['tokens']) + ' ' + str(j['estimate']['based_on'])")"
MINMACS_CLAUDE="$inv/no-such-claude" "$INV" investigate "$fx/in" --yes >"$inv/out.txt" 2>&1
check "a missing CLI fails and nothing else is tried" 1 "$(grep -c 'could not start no-such-claude' "$inv/out.txt")"

echo "  -- a finding, as the app runs it"
unset INV_TEST_SCRIPT
inv_fresh
"$INV" app investigate "invtest:server:fixture-app#dev" --yes >"$inv/out.txt" 2>&1
check "in the app it starts and returns at once" 1 "$(grep -c '^Started. The answer shows on its card' "$inv/out.txt")"
check "the finding's run reads only the app folder" True "$(inv_calls "'Folders: $fx/in' + chr(10) in c['prompt']")"
"$INV" investigate "invtest:server:fixture-app#dev" --json >"$inv/out.json"
check "the answer is saved with the finding" True "$(inv_get "j['last']['subject'] == 'invtest:server:fixture-app#dev' and j['last']['answer'].startswith('Fixture answer')")"
INV_TEST_SLEEP=3 "$INV" start "invtest:server:fixture-app#dev" >"$inv/start.out" 2>&1
check "inv start runs" 0 "$?"
while IFS="$inv_tab" read -r n w g; do check "$n" "$w" "$g"; done <"$inv/start.out"
check "no tool server is left running" 0 "$(inv_servers)"

echo "  -- the card"
"$INV" card >"$inv/card.out" 2>&1
check "inv card runs" 0 "$?"
while IFS="$inv_tab" read -r n w g; do check "$n" "$w" "$g"; done <"$inv/card.out"

echo "  -- the app binary serves its own tools"
export INV_TEST_SCRIPT="$inv/script.json"
inv_fresh
MINMACS_COLD=1 "$BIN" investigate "$fx/in" --yes --json >"$inv/out.json" 2>"$inv/err.txt"
check "MinMacs investigate --yes runs" 0 "$?"
check "and MinMacs is the tool server, with the same refusals" "minmacs 5 10" "$(inv_tools "head['server'] + ' ' + str(sum(not c['error'] for c in calls)) + ' ' + str(sum(c['error'] for c in calls))")"
grep -q "OUTSIDE_SECRET_42" "$INV_TEST_SENT.tools";       check "and nothing outside reaches the model" 1 "$?"
check "no tool server is left running after it" 0 "$(inv_servers)"

unset MINMACS_CLAUDE MINMACS_CODEX INV_TEST_SENT INV_TEST_SCRIPT INV_APP
export MINMACS_HOME="$inv_top"
