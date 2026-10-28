# The review

Some findings need judgment that rules cannot give, such as whether a dev server that has been quiet since lunch is still wanted, or whether a merged worktree with a few files changed last week can go. MinMacs asks a model about those. One review broker in Core does all the asking for every expert. An expert never calls a model itself.

This page says what the broker does and what it cost on a fixture day. [PRIVACY.md](PRIVACY.md) lists every field it sends. The code is `Sources/Core/Review/MMReview.h`, `MMReview.m`, `MMModel.m` and `MMInvestigate.m`. The numbers come from [docs/2.0/MEASUREMENTS.md](2.0/MEASUREMENTS.md), sections Review and Investigate.

## Which model, and how

- **The CLI on the person's own login.** The broker runs `claude -p` with Haiku. When `claude` is missing, signed out, out of usage or fails another way, it runs `codex exec` with a Luna model. The `review.model` pref picks auto, haiku, sonnet, opus or luna, and auto is the default.
- **No tools.** Every call to `claude` passes `--tools ""`, `--strict-mcp-config`, `--setting-sources ""` and `--no-session-persistence`, and runs in a fresh empty folder, so no project file is picked up. `codex` runs with every tool off and a read-only sandbox.
- **No API key.** `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN` and the variables of a Claude Code session that launched MinMacs are removed from the call's environment.
- **A JSON schema.** The answer must match a schema in the expert's own words: for LocoHost the verdicts are `in_use`, `idle` and `unsure`, for WorkForest `active`, `stale` and `unsure`. Core stores keep, go and unsure underneath.
- **Confidence.** Below 0.6 a verdict counts as unsure. At 0.8 or above a mode may act on it by itself.

## When it runs

- **On a schedule.** Core wakes each expert's review every hour, the first one a minute after launch. Wakes for one expert are at least 10 minutes apart, and wakes that come in between join the next one.
- **When asked.** Review Now in a menu, `minmacs review <expert> --now`, or an expert's own review verb. A manual review skips the 10 minute gap.
- **Within a budget.** By default the day allows 652,000 uncached tokens, a fifth of the 3.26M that research F measured for the old apps. Once the day is over, a scheduled review waits. A manual review still runs.

## Triage: who decides each finding

The broker goes through four steps for every finding, in this order. The first step that gives a verdict decides it.

1. **The expert's rules.** A rule decides with no model call, such as LocoHost's "not a dev server" or WorkForest's "holds work". A rule decides again on every review.
2. **Core's work keeps,** rule `core.work-keeps`. A finding with a work keep, such as an agent session active today, is kept with its first keep reason.
3. **The fingerprint cache.** An earlier verdict of the model or the judge carries over while three keys hold. See below.
4. **The model,** for what is left.

On the fixture day, of 3,177 findings that reached the broker:

| Decided by | Findings | Share |
|---|---|---|
| Rules | 1,591 | 50.1 % |
| The fingerprint cache | 1,492 | 47.0 % |
| The model | 94 | 3.0 % |

Another 528 never reached the broker. Insomnia asks for no review. MinMacs and Noo-Noo ask only about findings that propose an action, and their rules, `minmacs.lists` and `noonoo.owner-state`, decide every one of those. So in the current code neither of them sends a finding to the model.

Each saved review records `decided`, the count per rule id plus `cache`, `model` and `judge`, and `sent`, the number of findings sent to the model.

## Fingerprints

A fingerprint is a short string an expert makes from the facts that would change its verdict. LocoHost's holds the server's instance, its state, whether a client has it open and how long it has been quiet, in age buckets. WorkForest's holds HEAD, the merge state, the upstream, the counts of changed and untracked files and of unpushed commits, whether anything runs inside, and the session's age bucket.

A cached verdict carries over only while all three of these hold:

1. **The fingerprint.** Facts that only drift inside one bucket do not move it.
2. **The instance key.** For LocoHost that is the pid and start time, so a server that restarted is asked about again.
3. **The context,** from `MMReviewContext` in Core. It is the HEAD of the worktree that holds the finding, the activity bucket of the newest agent session there, and a size bucket of what the finding frees.

A rule's verdict is never cached, so a keep that ends goes to the model at the next review. With the cache off, the fixture day sent 1,586 findings and 734,945 uncached tokens. With it on, 94 findings and 56,846 tokens. The cache removed 94.1 % of the findings the rules left, and 92.3 % of their uncached tokens.

## Fact blocks

The findings of one call are grouped into one block per top owner, which is the workstream when there is one. The input looks like this, with every field described in [PRIVACY.md](PRIVACY.md):

```json
{"all": {...}, "blocks": [{"w": "~/code/app", "ws": {...}, "f": [{"id": "...", ...}, ...]}], "now": "2026-10-28T09:00:00+01:00"}
```

- **`f`** lists each finding's own facts and its `id`.
- **`ws`** holds the values of the expert's shared keys that every finding of a block of two or more has in common. LocoHost's shared keys are the agent session, branch, project, project files, repo activity and worktree. WorkForest's are the agent session, repo and default branch.
- **`all`** holds the values that every finding of a call of two or more shares.
- **Compact.** The input is compact JSON with sorted keys. Every null, false, zero and empty value is dropped.
- **One cached prefix.** Every system prompt ends with the same fixed note on how to read blocks, `ws` and `all`, so the prompt and schema stay one cached prefix. The cache lasts one hour when the expert's last review is less than an hour old, and five minutes otherwise.
- **Batches.** Calls hold at most 25 findings, three calls at a time.

On the 75 inputs the old apps' way of asking sent on the fixture day:

| Encoding | Bytes | Against pretty |
|---|---|---|
| Pretty-printed, as the 0.1 apps sent | 1,408,944 | 100 % |
| Compact with sorted keys | 928,658 | 66 % |
| Compact, null, false, zero and empty values dropped | 718,587 | 51 % |
| And values every finding of a call shares sent once, in `all` | 649,923 | 46 % |

In the broker's day, `ws` saved 70 uncached tokens: 56,916 without it, 56,846 with it. Only LocoHost's two servers in one worktree shared a block.

## The judge and the summary

- **The judge.** In Eager mode, findings the model decided but did not call a sure go get a second call. The burden of proof is on the finding: it stays only when a concrete fact shows someone still needs it. A failed judge keeps every finding it was asked about, and the next review asks again.
- **The summary.** The two or three sentences at the top of a menu come from the model. The counts come from code, and the prompt tells the model not to count. With more than one batch, one more call writes the summary from one line per finding: its id, title, verdict and what the verdict is about.

## Tokens a day

The fixture is one generated day for all five experts, from `test/review/dayfix.py`, replayed through `test/review/day.m`. It is made up, not recorded on a real Mac. A fake `claude` answered every call and counted 4 bytes of UTF-8 as one token, so the totals rest on that guess. Uncached tokens are input plus both cache writes plus output. Cache reads are left out.

| Run | Uncached tokens | As counted before | List cost |
|---|---|---|---|
| The 1.x way: LocoHost every hour, WorkForest every two hours, every finding sent | 1,842,725 | 1,879,463 | $0.7787 |
| The broker with the cache off, `--fresh` | 734,945 | 774,065 | $0.2564 |
| The broker | 56,846 | 58,476 | $0.0173 |

| Expert | 1.x uncached | Broker uncached | Broker calls | Findings sent |
|---|---|---|---|---|
| WorkForest | 1,630,277 | 39,915 | 12 | 75 of 2,313 |
| LocoHost | 212,448 | 16,931 | 11 | 19 of 120 |
| MinMacs, Noo-Noo, Insomnia | 0 | 0 | 0 | 0 |

- The broker's day is 3.1 % of the 1.x replay. `./test.sh review` fails above a fifth.
- Where both runs reviewed the same finding at the same tick, 1,224 of 1,274 verdicts were the same. The broker never said go where the 1.x review said keep or unsure, and the test checks that.
- The same replay on a real login, with the CLI's own counts, has not run yet.

## Investigate

Investigate is one deeper look, only when the person asks, at one finding, one workstream or one folder. LocoHost and WorkForest offer "Investigate…" on their cards. The CLI is `minmacs investigate <finding|workstream|path> [question]`, which shows the folders, the question, the estimate and the model, and runs only with `--yes`.

- **The folders.** The finding's folder, its owner's worktree and its workstream's worktree. A file stands for its folder. The root, the home folder and any folder above it are never used.
- **Its own tools.** Every built-in tool of Claude Code is off. The only tools are MinMacs's own Read, Grep and Glob, which the same binary serves over MCP as the hidden verb `_investigate-tools`. Each path is resolved with realpath and refused when it is outside the folders. Read checks the opened file again. Grep and Glob never follow a symlink.
- **No secrets.** Files named like `.env`, keys, `.netrc`, `.npmrc` and credential files are never read. Each line Read or Grep hands back goes through the same redaction as the review.
- **Bounded.** At most 12 turns. One Read hands back at most 512 KB of a file, and one call's output stops at 100 KB.
- **Audited.** Each tool call writes one audit line. The run saves the count of calls and refusals.

In the test, 10 of 15 scripted tool calls try to leave the folder or reach a secret, through an absolute path, `..`, a symlink, a symlinked folder, a sibling folder with the same prefix, `.env`, a Grep through the symlink, a glob with `..`, an absolute glob and a tool named Bash. All 10 are refused, and no byte of the outside files or of `.env` reaches the fake model.

Before a run the alert shows an estimate. Before the first run it is 35,000 tokens on Haiku. After that it is the median uncached tokens of the last five runs that answered. One call sends a system prompt of 426 characters, three tool schemas of 1,088 bytes, and a message of 224 to 242 bytes on the fixture. The tokens and time of a real run have not been measured, since that needs a paid call.
