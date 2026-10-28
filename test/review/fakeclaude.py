#!/usr/bin/env python3
# Stands in for the claude CLI in test/review.sh. Ported from LocoHost's tools/fakeclaude.py.
# Answers like `claude -p --output-format json --json-schema` with fakeanswer.py. Investigate has its own fake in test/investigate.
# It fails when tools are on for a review, when an API key reaches it, or when the effort flag is missing.
# With $RV_TEST_CLAUDE_LIMIT set it answers like an account that is out of usage, and with $RV_TEST_JUDGE_FAIL a judge call fails.
# Every call appends its folder, cache TTL and model to $RV_TEST_SENT.calls.
import json, os, sys
args = sys.argv[1:]
data = sys.stdin.read()
def fail(msg):
    print(json.dumps({"type": "result", "is_error": True, "result": msg, "total_cost_usd": 0.0, "usage": {}}))
    sys.exit(1)
sent = os.environ["RV_TEST_SENT"]
open(sent + ".calls", "a").write(json.dumps({"cli": "claude", "cwd": os.getcwd(), "ttl": os.environ.get("CLAUDE_CODE_PROMPT_CACHE_TTL", ""),
                                             "model": args[args.index("--model") + 1], "tools": args[args.index("--tools") + 1]}) + "\n")
if os.environ.get("RV_TEST_CLAUDE_LIMIT"): fail("Claude AI usage limit reached|1793880000")
if "ANTHROPIC_API_KEY" in os.environ: fail("fixture: an API key reached claude")
if "--effort" not in args: fail("fixture: no --effort")
usage = {"input_tokens": 10, "cache_creation_input_tokens": 300, "cache_read_input_tokens": 1000, "output_tokens": 50,
         "cache_creation": {"ephemeral_5m_input_tokens": 100, "ephemeral_1h_input_tokens": 200},
         "output_tokens_details": {"thinking_tokens": 30}}
if "--json-schema" not in args: fail("fixture: Investigate has its own fake, test/investigate/fakeclaude.py")
if args[args.index("--tools") + 1] != "": fail("fixture: tools are not off")
schema = args[args.index("--json-schema") + 1]
if os.environ.get("RV_TEST_JUDGE_FAIL") and '"decision"' in schema: fail("fixture: the judge fails")
import fakeanswer
so = fakeanswer.answer(data, schema)
print(json.dumps({"type": "result", "is_error": False, "result": "", "structured_output": so,
                  "total_cost_usd": 0.0001, "usage": usage}))
