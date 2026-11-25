#!/usr/bin/env python3
# Stands in for the claude CLI in test/ask.sh and test/window/ask.m, as test/review/fakeclaude.py does for the reviews.
# Answers like `claude -p --output-format json` with words, never a schema. Each call appends what it was sent, the
# plain text on stdin, to $ASK_FAKE_SENT, and one line per call to $ASK_FAKE_SENT.calls.
# $ASK_FAKE_MODE picks the answer: answer (the default), action (ends on ACTION: keep 3001), undo (ACTION: undo last), badaction (an action no
# rule knows), sleep (answers too late), fail (signed out). It fails when a tool is on, a schema is asked for, or an
# API key reaches it.
import json, os, sys, time
args = sys.argv[1:]
data = sys.stdin.read()
sent = os.environ.get("ASK_FAKE_SENT")
if sent:
    open(sent, "a").write(data + "\n=====\n")
    open(sent + ".calls", "a").write(json.dumps({"model": args[args.index("--model") + 1], "tools": args[args.index("--tools") + 1],
                                                 "effort": args[args.index("--effort") + 1] if "--effort" in args else "",
                                                 "cwd": os.getcwd(), "bytes": len(data.encode())}) + "\n")
def fail(msg, code=1):
    print(json.dumps({"type": "result", "is_error": True, "result": msg, "total_cost_usd": 0.0, "usage": {}}))
    sys.exit(code)
if "ANTHROPIC_API_KEY" in os.environ: fail("fixture: an API key reached claude")
if args[args.index("--tools") + 1] != "": fail("fixture: tools are not off")
if "--json-schema" in args: fail("fixture: Ask asks for words, not a schema")
mode = os.environ.get("ASK_FAKE_MODE", "answer")
if mode == "sleep":
    time.sleep(20)
if mode == "fail":
    print("Not logged in · Please run /login", file=sys.stderr)
    sys.exit(1)
turns = data.count("\nQ: ")
text = "Hello. I can say what MinMacs did, would clean or keeps. I saw %d earlier questions." % turns
if mode == "action": text = "Port 3001 runs Next.js and nothing asks for it.\nYou could keep it.\nACTION: keep 3001"
if mode == "undo": text = "The newest stop can still be taken back.\nACTION: undo last"
if mode == "badaction": text = "I would wipe the disk.\nACTION: delete everything"
usage = {"input_tokens": 40, "cache_creation_input_tokens": 200, "cache_read_input_tokens": 9000, "output_tokens": 60,
         "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 200}}
print(json.dumps({"type": "result", "is_error": False, "result": text, "total_cost_usd": 0.0002, "usage": usage}))
