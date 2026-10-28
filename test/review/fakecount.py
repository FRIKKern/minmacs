# How the fake claude counts the tokens of one call in the day replay. The same counting serves the 1.x baseline
# and the broker, so the two totals compare. MMBudget then sums what the fake reports, as it sums a real call.
# The rules each come from research F, docs/2.0/research/F-review-economics.md.
# - A token is 4 bytes of UTF-8. F assumes 3 to 4 bytes a token. This is the guess the totals rest on.
# - The system prompt and the schema are the cached prefix, F 1.4. A call reads it from cache when the same prefix
#   was used within the TTL on the replay's clock, and writes it otherwise. The TTL is the one the call asked for,
#   one hour when it asked for none, as Claude Code asks on a subscription, F 2.1.
# - The input on stdin is written to the cache at that TTL, F 1.4: the varying input is written, never read again.
# - input_tokens is 2 a call, the field F saw in its test calls.
# - Visible output is the bytes of the answer. Thinking is 4 times visible output at the default effort, F 1.4 and
#   1.5 put thinking at 76 to 85 percent of output, and 2 times at --effort low, F's guess A4 of a 50 percent cut.
# - The list cost uses Haiku 5.5's prices of F 1.3.
import fcntl, hashlib, json, os, time

def tokens(text):
    return (len(text.encode("utf-8")) + 3) // 4

def count(state_path, prefix, data, answer, effort, ttl):
    clock = float(os.environ.get("RV_TEST_CLOCK") or time.time())
    life = 300 if ttl == "5m" else 3600
    key = hashlib.sha1(prefix.encode("utf-8")).hexdigest()
    p = tokens(prefix)
    with open(state_path, "a+") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        fh.seek(0)
        try: state = json.loads(fh.read() or "{}")
        except ValueError: state = {}
        hit = key in state and clock - state[key] < life
        state[key] = clock
        fh.seek(0); fh.truncate(); fh.write(json.dumps(state))
    read, write = (p, 0) if hit else (0, p)
    write += tokens(data)
    visible = tokens(json.dumps(answer, separators=(",", ":")))
    thinking = visible * (2 if effort == "low" else 4)
    out = visible + thinking
    w5, w1 = (write, 0) if ttl == "5m" else (0, write)
    usage = {"input_tokens": 2, "cache_creation_input_tokens": write, "cache_read_input_tokens": read, "output_tokens": out,
             "cache_creation": {"ephemeral_5m_input_tokens": w5, "ephemeral_1h_input_tokens": w1},
             "output_tokens_details": {"thinking_tokens": thinking}}
    cost = (2 * 0.10 + w5 * 0.125 + w1 * 0.20 + read * 0.01 + out * 0.50) / 1e6
    return usage, cost
