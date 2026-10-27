# Research F: model review economics

Tracks [FRIKKern/minmacs#6](https://github.com/FRIKKern/minmacs/issues/6).

## Summary

- **Today.** The last LocoHost review used 14,175 tokens for 5 servers. The last WorkForest review used 243,061 tokens for 91 worktrees. At the default schedules that is about 3.26M tokens a day, before event reviews. The plan's 2.7M figure is in the same range.
- **Where the tokens go.** Output tokens, and mostly thinking tokens, are 30 to 48 percent of WorkForest's tokens and 53 to 85 percent of its cost. Haiku 5.5 thinks by default. In two test calls, thinking was 85 and 76 percent of the output.
- **Caching.** `claude -p` caches a repeated `--system-prompt`, with a one-hour TTL on a subscription. A second call read 1,470 tokens from cache. `codex exec` gets OpenAI's automatic prefix cache. This Mac's Codex logs show fresh sessions reading up to 51,712 cached tokens on their first turn.
- **The counter is misleading.** Both apps add `cache_read_input_tokens` to `tokens` at full weight. A cache read costs a tenth of an input token on Haiku 5.5.
- **Target.** The model below gives about 150k tokens a day for the 2.0 design, about 5 percent of today. With three times the churn, no rules and no thinking cut, it gives about 680k, which misses the plan's one-fifth goal of 540k. The biggest single lever is to send unchanged worktrees zero times.

## 1. What a review costs today

### 1.1 Measured from review.json

Both files were read on 2026-10-27, read only.

| | LocoHost | WorkForest |
|---|---|---|
| File | `~/Library/Application Support/LocoHost/review.json` | `~/Library/Application Support/WorkForest/review.json` |
| Model | `haiku` | `haiku` |
| Mode, trigger | eager, "high load 19.3" | idle, "new worktree barkpark/barkpark-catalog-sso" |
| Items | 5 hosts | 91 trees |
| `tokens` | 14,175 | 243,061 |
| `costUSD` | 0.00469404 | 0.06934795 |
| `seconds` | 29.6 | 143.1 |
| Tokens per item | 2,835 | 2,671 |

Each file keeps only the last review. No history of past reviews is stored, so the per-day figures below are computed from cadence, not counted.

### 1.2 How the apps count tokens

- **Claude.** `tokens` is `input_tokens + output_tokens + cache_creation_input_tokens + cache_read_input_tokens`. Source: `workforest/Sources/Review.m:220-223` and `locohost/Sources/Review.m:237-240`. Cache reads count at full weight here.
- **Codex.** `tokens` is `input_tokens + output_tokens` from the `turn.completed` event. Source: `workforest/Sources/Review.m:294-295` and `locohost/Sources/Review.m:308-310`. Codex reports `cached_input_tokens` as part of `input_tokens`. This Mac's Codex log shows `"input_tokens":574057872,"cached_input_tokens":565571840,...,"output_tokens":1538796,...,"total_tokens":575596668`, and input plus output equals the total. The sum holds in all 5,324 `token_count` events of that file. Source: the last `token_count` event in `~/.codex/sessions/2026/10/16/rollout-2026-10-16T10-53-38-*.jsonl`.
- **Neither app records thinking tokens or the cache split.** The `claude -p` JSON has `usage.output_tokens_details.thinking_tokens` and `usage.cache_creation.ephemeral_1h_input_tokens`. Source: the test calls in 1.4.

### 1.3 What "haiku" is

`claude -p --model haiku` answered as `claude-haiku-5-5`. Source: `modelUsage` in the test call output, `"canonicalModel": "claude-haiku-5-5"`. Haiku 5.5 costs $0.10 per million input tokens and $0.50 per million output tokens up to a 100K-token prompt. Thinking is on by default, with effort `medium`. Source: the claude-api skill, `shared/models.md:87`, bundled as skill version 2.1.310 with Claude Code 2.1.311. Cache reads cost about 0.1 times input. Cache writes cost 1.25 times input with the five-minute TTL and 2 times with the one-hour TTL. Source: the same skill, `shared/prompt-caching.md:144`.

### 1.4 Two test calls

I ran two small paid calls, the limit for this track. Both used WorkForest's exact flags from `workforest/Sources/Review.m:206-207`, its real `kSystem` prompt, a one-field schema and a one-worktree input. The input differed between the calls. The same environment variables were removed as in the app.

| | Call 1 | Call 2 |
|---|---|---|
| `cache_creation_input_tokens` | 2,163, all `ephemeral_1h` | 693, all `ephemeral_1h` |
| `cache_read_input_tokens` | 0 | 1,470 |
| `output_tokens` | 925 | 1,689 |
| of which `thinking_tokens` | 788 | 1,277 |
| `total_cost_usd` | 0.0008953 | 0.000998 |

The prices in 1.3 reproduce both costs exactly. Call 1 is 2,163 × $0.20/M + 925 × $0.50/M = $0.000896. Call 2 is 693 × $0.20/M + 1,470 × $0.01/M + 1,689 × $0.50/M = $0.000998. That confirms the one-hour write rate of 2 times input.

What the calls show:
- The fixed part of each call is 1,470 tokens: the system prompt, the schema and what Claude Code adds. It is read from cache on the next call.
- The varying input is written to the one-hour cache at twice the input price, though no later call will read it.
- For one short answer, the model spent 788 to 1,277 thinking tokens.

### 1.5 Splitting WorkForest's 243k

The review ran 4 batches of 25 at most, 3 at a time, plus one summary call. Source: `workforest/Sources/Review.m:5-6` and `:464-466`. With the prices in 1.3, two equations hold: tokens = C + R + O, and cost = 0.20·C + 0.01·R + 0.50·O in dollars per million. C is cache writes, R is cache reads and O is output. The input field adds about 2 per call, so it is ignored. Solving gives O = 69.1k + 0.633·R.

- R is at least about 6k, the fixed 1,470 tokens read by most of the 5 calls. This is a guess from call 2. Then O is about 73k, 30 percent of tokens, and $0.037 of the $0.069.
- C must still hold the facts. One sample worktree encodes to 1,146 bytes in the app's pretty-printed JSON, so 91 trees are at least about 30k to 50k tokens. This is a guess: the bytes come from a script I ran, and the bytes-per-token ratio is assumed. With C at 50k or more, R is at most 76k, O at most 117k, which is 48 percent of tokens and $0.058 of the cost.

Each tree's answer, as JSON in `review.json` with its keys, averages 712 bytes. The string values alone average 554 bytes. At an assumed 3 to 4 bytes a token, 712 bytes a tree gives about 16k to 22k tokens for 91 trees. The rest of O, roughly 50k to 100k, is thinking. LocoHost gives the same picture: O = 6.2k + 0.633·R, so output is 44 to 50 percent of its 14,175 tokens.

### 1.6 Tokens a day today

| Expert | Schedule | Event reviews | Per review | Per day, schedule only |
|---|---|---|---|---|
| LocoHost | every 60 min, `locohost/Sources/main.m:16` | at least 10 min apart, `main.m:30` and `:906` | 14,175 | 340,200 |
| WorkForest | every 120 min, `workforest/Sources/main.m:14` | at least 30 min apart, `main.m:19` and `:413` | 243,061 | 2,916,732 |
| Total | | | | 3,256,932 |

PLAN.md §4 gives 18k an hour and 190k every two hours, which is 2,712,000. The figures differ because WorkForest's worktree count changes. Event reviews come on top of both. The list cost of the schedule alone is about $0.11 a day for LocoHost and $0.83 for WorkForest. Whether a subscription's usage limit weighs cache reads like other tokens is not documented in the sources I read.

## 2. Does the CLI cache a repeated system prompt?

### 2.1 claude -p: yes

- Call 2 in 1.4 read 1,470 tokens from cache that call 1 wrote. This was a separate process with `--no-session-persistence`.
- Claude Code docs: "Unless you choose a TTL yourself, Claude Code requests the one-hour TTL only on a Claude subscription within your plan's included usage." Non-interactive `-p` runs are in the "Main conversation" bucket. Source: [How Claude Code uses prompt caching](https://code.claude.com/docs/en/prompt-caching.md), section "Which TTL each request gets".
- The TTL can be set with `CLAUDE_CODE_PROMPT_CACHE_TTL` set to `5m` or `1h`, or forced short with `FORCE_PROMPT_CACHING_5M=1`. `DISABLE_PROMPT_CACHING_HAIKU` turns caching off for the `haiku` alias. Source: the same page, sections "Choose the TTL yourself" and "Disable prompt caching".
- `--effort <level>` takes low, medium, high, xhigh or max. Source: `claude --help` on Claude Code 2.1.311.
- `--exclude-dynamic-system-prompt-sections` does nothing for us: "ignored with --system-prompt". Source: `claude --help`.
- Interactive sessions on this Mac show the same effect. The first message of 19 recent sessions read 7,015 to 28,415 tokens from cache. Source: the first `usage` object in each of the 20 newest files under `~/.claude/projects/*/*.jsonl`.

### 2.2 codex exec: yes, by OpenAI's automatic prefix cache

- OpenAI docs: "Prompt caching is enabled by default for supported OpenAI models." The minimum is 1,024 tokens for GPT-5.6 and later. Cached prefixes stay at least 30 minutes. They are reported as `usage.input_tokens_details.cached_tokens`, at a discount of up to 95 percent. Source: [OpenAI prompt caching guide](https://developers.openai.com/api/docs/guides/prompt-caching).
- This Mac shows caching across processes. Of 25 recent Codex sessions, 19 read from cache on their first turn. Three sessions started at 13:03:16, 13:03:29 and 13:03:35 on 2026-10-19 read 46,720, 48,128 and 48,128 cached tokens on their first turn. Source: the first `last_token_usage` in each rollout file under `~/.codex/sessions/2026/10/`.
- Not shown: whether the `--ephemeral` exec runs the apps use hit the cache. No exec rollouts exist on this Mac, because `--ephemeral` writes none. WorkForest's system prompt is about 1,470 tokens with the schema, above the 1,024 minimum. This is a guess, since Codex wraps it in its own instructions.
- The apps already use `model_reasoning_effort="low"` on Codex. Source: `workforest/Sources/Review.m:274`.

### 2.3 What caching does not fix

The system prompt is about 1,470 of the 2,163 to 2,800 tokens per item, and it is already cheap after the first call. The cost is in the varying facts and in output. Caching cannot reduce either one. Caching also adds cost here: the one-hour TTL bills one-shot facts at 2 times input, against 1.25 times with five minutes.

One more guess: the prompt JSON is written without sorted keys. Source: `workforest/Sources/Review.m:401`. So whether `now` or `worktrees` comes first is up to NSDictionary. If `worktrees` comes first, an unchanged batch could read its facts from cache. That would explain a larger R in 1.5. I did not test this.

## 3. Ways to cut tokens

### 3.1 Fact compression

The app writes facts with `NSJSONWritingPrettyPrinted`. Source: `workforest/Sources/Review.m:401` and `locohost/Sources/Review.m:415`. One sample worktree, encoded by a script I ran:

| Encoding | Bytes |
|---|---|
| Pretty-printed, as today | 1,146 (unverified) |
| Compact | 956 (unverified) |
| Compact, with null, false, 0, empty fields dropped | 799 (unverified) |

That is 30 percent fewer input bytes (unverified: the script and the sample were not saved). Short keys would save more, but they make the system prompt harder to read and are not measured here. One block per workstream removes facts that LocoHost and WorkForest both send today, such as session titles and server lists. Source: PLAN.md §4, item 3. Its size was not measured.

### 3.2 Smaller answers

The four prose fields `what`, `why`, `state` and `recommendation` are 66 percent of WorkForest's answer text. In LocoHost, `what`, `why`, `how`, `recommendation` and `waste` are 61 percent. Source: string lengths summed per field in each `review.json`. The routine review needs `verdict`, `confidence`, `about`, `reason` and `keep_evidence`. Several prose fields could be built from facts, or asked of the model only when a card is opened.

### 3.3 Less thinking

Thinking is most of the output, as 1.4 shows. `claude -p --effort low` is available. How much it cuts on Haiku 5.5 is not measured. The two-call budget was used on the caching question. The model below assumes a 50 percent cut, and that is a guess.

### 3.4 Fingerprint caching

A finding goes to the model only when its fingerprint changed. Source: PLAN.md §4, item 2. Churn measured from `~/Library/Application Support/WorkForest/facts.json` on 2026-10-27, 114 entries:
- 30 have a last commit in the past 24 hours.
- 28 were created in the past 24 hours.

Today every review sends all 91 trees. At 12 scheduled reviews that is 1,092 tree reviews a day. If only changed trees are sent, and each changes about twice a day as activity buckets cross, about 80 tree reviews remain. That rate is an assumption.

### 3.5 Rules-first triage

The last WorkForest review gave 38 active, 20 stale and 33 unsure. 37 of 91 verdicts have a confidence of 0.8 or more, and 41 have 0.75 or more. Source: `review.json`. In `facts.json`, 66 of 114 entries are merged in some way: 34 ancestor, 19 squash, 12 patch, 1 tree. Rules can decide "uncommitted changes", "process or server inside", "session active in the last day" and "merged and quiet for days". The model assumes rules decide half of the changed trees. Of LocoHost's 5 hosts, PostgreSQL and epmd are services a rule can keep, so 3 need the model.

## 4. Model of a normal day for 2.0

### 4.1 Assumptions

| # | Assumption | Value | Basis |
|---|---|---|---|
| A1 | Tokens per item today | 2,671 per tree, 2,835 per host | measured, 1.1 |
| A2 | Split of those tokens | 50 percent input, 50 percent output, 80 percent of output thinking | 1.4 and 1.5, rounded; guess within the measured range |
| A3 | Compression | input × 0.70, visible output × 0.34 | 3.1 and 3.2; the output share is measured, the input factor is unverified |
| A4 | Thinking cut from `--effort low` | 50 percent | guess, not measured |
| A5 | Changed trees sent a day | 80 | 3.4, churn measured, rate assumed |
| A6 | Share of changed trees the rules cannot decide | 0.5 | 3.5, guess |
| A7 | LocoHost host reviews a day | 18, which is 3 hosts × 6 changes | guess |
| A8 | Fixed part per call | 1,500 tokens, 12 calls a day per expert | 1.4 |
| A9 | Summaries | 6 a day × 3,000 tokens | guess; one per change in verdicts |
| A10 | Counting | the apps' current sum, cache reads at full weight | 1.2 |

Per-item factor: 0.5 × 0.70 + 0.1 × 0.34 + 0.4 × 0.5 = 0.584.

### 4.2 Result

These figures come from a script I ran with the assumptions above.

| Case | WorkForest | LocoHost | Total a day | Against 2.7M |
|---|---|---|---|---|
| Today, schedule only, measured basis | 2,916,732 | 340,200 | 3,256,932 | 121% |
| Target, A1 to A10 | 98,395 | 47,802 | 146,196 | 5.4% |
| Target, no thinking cut, A4 = 0 | 119,763 | 58,008 | 177,770 | 6.6% |
| Target, thinking cut 80% | 85,574 | 41,678 | 127,252 | 4.7% |
| Bad day: 3× churn, no rules, no thinking cut | 538,575 | 138,023 | 676,598 | 25% |

Most of the saving comes from A5 and A6: 40 tree reviews a day against 1,092. Compression and less thinking bring each review down to about 58 percent of today's size. The bad-day row misses the one-fifth goal. So the fingerprint cache and the rules carry the target, and the cache must work from day one.

### 4.3 Model choice

- **Haiku 5.5** is the measured default: $0.10 and $0.50 per million. Source: 1.3.
- **Luna through codex** runs with `model_reasoning_effort="low"`. Source: `workforest/Sources/Review.m:274`. No Luna review output with token counts exists on this Mac. I found no price for Luna in the sources I read.
- **A local model.** I found no evidence on this Mac or in the sources I read. Quality on our fixtures is unknown.

### 4.4 The Investigate agent

Investigate would run Claude Code with read-only tools. Claude Code's default prompt and tools are large. On this Mac the first turn of a session reads 7k to 28k tokens from cache and writes 3k to 35k. Source: 2.1. A run of 10 turns that each re-read about 40k would count about 400k tokens under A10, mostly cache reads. This is a guess. A custom `--system-prompt` with only Read, Grep and Glob would shrink that base, as the routine review's 1,470-token prefix shows. Investigate runs only when the user asks, so it is not in the daily total.

## Recommendations

1. **PLAN.md §4, item 2. Build the fingerprint cache first in phase 4.** It carries most of the saving: 1,092 tree reviews a day down to about 40 under A5 and A6. Shared pattern: the review broker's fingerprint store.
2. **PLAN.md §4, item 1. Write the rules as data, and log how many findings each rule decides.** Then A6 becomes a measured number. Shared pattern: rules-first triage in the broker.
3. **PLAN.md §4, item 4. Pass `--effort low` to `claude -p`.** Then measure the thinking cut against the recorded fixture before you rely on it. Codex already runs at low effort. Shared pattern: the broker's model call.
4. **PLAN.md §4, item 4. Set `CLAUDE_CODE_PROMPT_CACHE_TTL=5m` on review calls when calls of one expert run more than an hour apart.** One-shot facts would then be written at 1.25 times input instead of 2 times. Keep `1h` when calls come within the hour, so the system prompt stays cached. Shared pattern: the broker's model call.
5. **PLAN.md §4, item 3. Send compact JSON, drop null, false and zero fields, and sort keys with stable facts first.** This cut 30 percent of input bytes on a sample (unverified). Shared pattern: workstream fact blocks in the graph.
6. **PLAN.md §4, item 4. Keep the routine schema to verdict, confidence, about, reason and keep_evidence.** Build the prose fields from facts, or ask for them when a card opens. They are 61 to 66 percent of answer text today. Shared pattern: the per-expert schema.
7. **PLAN.md §9, phase 4. Record the full usage split per call:** input, cache write by TTL, cache read, output and thinking, plus `total_cost_usd`. The phase 4 "Done when" test needs it. Report cost alongside tokens, because the current sum counts cache reads at full weight. Shared pattern: the review record in Store.
8. **PLAN.md §9, phase 4. Keep a review history, not only the last review.** Today's per-day numbers are computed from cadence because each file keeps one review. Shared pattern: Store's append-only logs.
9. **PLAN.md §4, item 4, Investigate. Run it with a custom `--system-prompt` and only Read, Grep and Glob, scoped to the workstream's folders.** Measure its first run and set a token budget from that. Shared pattern: the broker's agent call.

## Open questions

1. How much does `--effort low` cut Haiku 5.5's thinking on a real batch, and do the verdicts stay the same on the fixture? This needs paid calls beyond this track's budget.
2. Does a Claude subscription's usage limit weigh cache reads and one-hour writes like other tokens? The sources I read do not say.
3. Do `codex exec --ephemeral` runs read OpenAI's prefix cache across processes, as interactive Codex sessions on this Mac do?
4. What does Luna cost on a ChatGPT login, and how do its verdicts compare with Haiku 5.5 on the fixture?
5. Is there a local model good enough for the routine review? No evidence was found.
6. How often do event reviews fire on a normal day? Neither app logs them today.
7. Does Claude Code accept a way to turn thinking off for `-p`, beyond `--effort`? `claude --help` shows none.

## Verification

A second pass checked every factual claim on 2026-10-27. All commands were read only. No paid model calls were made.

**What was checked.**
- Both `review.json` files: model, mode, trigger, item counts, `tokens`, `costUSD`, `seconds`, verdict counts, confidence values and per-field string lengths. Each file holds one review object.
- `workforest/Sources/Review.m` lines 5-6, 206-207, 220-223, 274, 294-295, 401, 440 and 464-466. `locohost/Sources/Review.m` lines 237-240, 308-310 and 415. Neither app reads `thinking_tokens` or the cache split, by grep.
- `locohost/Sources/main.m` lines 16, 30 and 906. `workforest/Sources/main.m` lines 14, 19 and 413.
- The saved test call outputs `scratchpad/f/call1.json` and `call2.json`, and `scratchpad/f/system.txt` against `kSystem`. Both costs reproduce from the stated prices.
- The claude-api skill files `shared/models.md:87` and `shared/prompt-caching.md:144`, and `claude --help` on 2.1.311.
- `~/Library/Application Support/WorkForest/facts.json`: 114 entries, 30 with a commit and 28 created in the past 24 hours, and the merge kinds.
- `~/.codex/sessions/2026/10/`: the rollout file in 1.2, first-turn cached tokens per session, and the session originators. No `codex exec` session exists.
- `~/.claude/projects/*/*.jsonl`: the first usage object in the 20 newest files.
- [How Claude Code uses prompt caching](https://code.claude.com/docs/en/prompt-caching.md) and the [OpenAI prompt caching guide](https://developers.openai.com/api/docs/guides/prompt-caching), fetched again.
- PLAN.md §4 and §9.
- All arithmetic in 1.5, 1.6, 4.1 and 4.2, recomputed by hand. Every row of the 4.2 table reproduces.

**Corrected.**
1. 1.2: the quoted Codex numbers came from line 38284, not the last `token_count` event. The text now quotes the last event.
2. 1.3: the skill is bundled as version 2.1.310, under Claude Code 2.1.311.
3. 1.5: the summary call is at `Review.m:464-466`, not `:466` alone.
4. 1.5: the solved constant is 69.1k, not 69.2k.
5. 1.5: the 712 bytes per tree is each answer as JSON with its keys. The string values alone are 554 bytes.
6. 3.2 and recommendation 6: LocoHost's prose fields are 61 percent of answer text, not 62.
7. 3.5: 37 of 91 verdicts have confidence 0.8 or more. The draft said 41, which is the count at 0.75 or more.

**Unsupported.**
1. 3.1: the byte sizes 1,146, 956 and 799 for one sample worktree. The script and the sample were not saved, so they cannot be rerun.
2. 3.1 and recommendation 5: the 30 percent input saving, which rests on that table. The A3 input factor of 0.70 rests on it too.

Claims the draft already marked as guesses or assumptions were left as they are and are not counted.

**Counts.** Confirmed 56, corrected 7, unsupported 2.
