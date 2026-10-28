#!/usr/bin/env python3
# Stands in for `claude -p` in test/investigate.sh. It never reaches a model.
# It checks the flags Investigate must pass, starts the MCP server named in --mcp-config the way Claude Code does,
# lists its tools, makes the tool calls in $INV_TEST_SCRIPT, a JSON list of {"name", "arguments"}, and answers with
# a summary of what the tools returned. Every call appends its flags to $INV_TEST_SENT.calls, and every tool result
# to $INV_TEST_SENT.tools. $INV_TEST_OUTPUT sets output_tokens, $INV_TEST_FAIL makes the call fail.
import json, os, subprocess, sys
args = sys.argv[1:]
prompt = sys.stdin.read()
sent = os.environ["INV_TEST_SENT"]
def flag(name, default=None):
    return args[args.index(name) + 1] if name in args else default
def fail(msg):
    print(json.dumps({"type": "result", "is_error": True, "result": msg, "total_cost_usd": 0.0, "usage": {}}))
    sys.exit(1)
record = {"cwd": os.getcwd(), "model": flag("--model"), "tools": flag("--tools"), "allowed": flag("--allowedTools"),
          "max_turns": flag("--max-turns"), "effort": flag("--effort"), "strict": "--strict-mcp-config" in args,
          "setting_sources": flag("--setting-sources"), "system": flag("--system-prompt"), "prompt": prompt,
          "api_key": "ANTHROPIC_API_KEY" in os.environ, "schema": "--json-schema" in args}
open(sent + ".calls", "a").write(json.dumps(record) + "\n")
if record["api_key"]: fail("fixture: an API key reached claude")
if record["tools"] != "": fail("fixture: the built-in tools are not off")
if record["allowed"] != "mcp__minmacs__Read,mcp__minmacs__Grep,mcp__minmacs__Glob": fail("fixture: the allowed tools are wrong")
if os.environ.get("INV_TEST_FAIL"): fail("fixture: the run fails")
config = json.loads(flag("--mcp-config", "{}"))
servers = config.get("mcpServers", {})
if list(servers) != ["minmacs"]: fail("fixture: the only MCP server must be minmacs")
srv = servers["minmacs"]
env = dict(os.environ); env.update(srv.get("env", {}))
p = subprocess.Popen([srv["command"]] + srv.get("args", []), stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env, text=True)
n = 0
def rpc(method, params=None, notify=False):
    global n
    msg = {"jsonrpc": "2.0", "method": method, "params": params or {}}
    if not notify:
        n += 1; msg["id"] = n
    p.stdin.write(json.dumps(msg) + "\n"); p.stdin.flush()
    if notify: return None
    line = p.stdout.readline()
    if not line: fail("fixture: the tool server closed")
    reply = json.loads(line)
    if reply.get("id") != n: fail("fixture: the reply id does not match")
    return reply
init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "fakeclaude", "version": "0"}})
rpc("notifications/initialized", notify=True)
names = [t["name"] for t in rpc("tools/list")["result"]["tools"]]
unknown = rpc("resources/list")
script = json.load(open(os.environ["INV_TEST_SCRIPT"])) if os.environ.get("INV_TEST_SCRIPT") else []
ok = refused = 0
with open(sent + ".tools", "a") as out:
    out.write(json.dumps({"server": init["result"]["serverInfo"]["name"], "tools": names, "unknown_method": unknown.get("error", {}).get("code")}) + "\n")
    for call in script:
        r = rpc("tools/call", {"name": call["name"], "arguments": call.get("arguments", {})})["result"]
        text = "".join(c.get("text", "") for c in r["content"])
        out.write(json.dumps({"name": call["name"], "arguments": call.get("arguments", {}), "error": r["isError"], "text": text}) + "\n")
        if r["isError"]: refused += 1
        else: ok += 1
p.stdin.close()
p.wait(timeout=10)
import time
time.sleep(float(os.environ.get("INV_TEST_SLEEP", "0")))
usage = {"input_tokens": 10, "cache_creation_input_tokens": 300, "cache_read_input_tokens": 1000,
         "output_tokens": int(os.environ.get("INV_TEST_OUTPUT", "50")),
         "cache_creation": {"ephemeral_5m_input_tokens": 100, "ephemeral_1h_input_tokens": 200}}
print(json.dumps({"type": "result", "is_error": False, "num_turns": len(script) + 1,
                  "result": "Fixture answer: %d tool calls answered and %d refused. The key is API_TOKEN=FIXTURESECRET1." % (ok, refused),
                  "total_cost_usd": 0.0002, "usage": usage}))
