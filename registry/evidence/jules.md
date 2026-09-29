# Jules: evidence notes (2026-09-29)

Row: `registry/agents/jules.json`. Validator: `ok`. Confidence `documented`. Not installed on this Mac and nothing was run: `which jules` printed `jules not found`, `ps` showed no jules process, `ls /Applications | grep -iE 'jules|pievra'` and `ls ~/.jules ~/.config/jules` found nothing.

## What I checked
- Official docs, 29 pages under https://jules.google/docs/ (getting started, running tasks, review plan, code, repo, integrations, environment, scheduled and suggested tasks, limits, faq, errors, API quickstart/auth/sources/sessions/activities/types, CLI reference and examples, six changelog entries). Changelog runs to 2026-03-09; no newer surface is announced.
- npm `@google/jules` 0.1.42 (2025-12-16, still latest; `latest: v0.1.42` in `storage.googleapis.com/jules-cli/latest/metadata.yaml`). Unpacked the tarball to scratch and read `index.cjs` and `run.cjs` in full.
- The vendor binary for darwin_arm64, downloaded to scratch, never executed or installed. Read with `file`, `codesign -dv`, and python regex over the bytes (the shell's `grep` is ugrep and chokes on long patterns).
- npm `@google/jules-sdk` 0.2.0 (2026-03-09): read `dist/index.mjs` for local file paths.
- Gemini CLI extension README (`gemini-cli-extensions/jules`), `jules-action` and `jules-skills` repo descriptions. The Go CLI source is not public: `google-labs-code/jules-awesome-list`, which npm names as the repo, holds prompts only.

## Answers per field
| Field | Answer | Basis |
|---|---|---|
| Nature | Cloud agent. Every task runs in a fresh Google VM that clones the GitHub repo. Nothing that does the work runs on the Mac | docs faq |
| Local surface | Jules Tools only: a Go client. Interactive TUI (`jules`), plus one-shots `jules new`, `jules remote list/new/pull`, `jules teleport <id>`. Also `login`, `logout`, `version`, `completion` | CLI reference, binary help text |
| Process name | `jules` (Mach-O arm64, Go 1.24.8, module `jules-cli`). npm launcher `node .../run.cjs` is a separate parent process named `node` | run.cjs, `file` |
| Paths | npm global: `<prefix>/bin/jules` (here `~/.nvm/versions/node/v22.22.2/bin/jules`); npx: `$TMPDIR/jules_tmp/jules`, child of `node .../run.cjs` | index.cjs `getInstallationPath`, run.cjs `installPath` |
| Bundle ids | None. No app, no Info.plist (`codesign`: `Identifier=a.out`, `Info.plist=not bound`). No first-party macOS app found; the only Mac/iOS hit was a third-party "Pievra" app | codesign, App Store search |
| Process to session | Not possible from argv. `teleport` takes the id positionally; `remote pull --session <id>`; but `remote new --session "<prompt>"` uses the same flag for the prompt. The TUI takes none | binary help text |
| Store | Server-side, reachable by REST (`jules.googleapis.com/v1alpha`, header `x-goog-api-key`). No local transcript from Jules Tools. Only local files: the JS SDK cache `<root>/.jules/cache/<sessionId>/activities.jsonl` + `metadata.json` + `.jules/cache/sync-checkpoint.json` (root = `$JULES_HOME`, else cwd with a package.json, else `$HOME`, else `$TMPDIR`) | SDK `getRootDir()` |
| Turn in progress | Server state `QUEUED`, `PLANNING`, `IN_PROGRESS`. Not visible locally. Weak local proxy: CPU of the client | API docs |
| Waiting on human | Server state `AWAITING_PLAN_APPROVAL`, `AWAITING_USER_FEEDBACK` (activities `planGenerated`, `agentMessaged`). Browser notification when a plan is ready or input is needed | API docs, getting started |
| Hooks | None | 29 pages grepped |
| OpenTelemetry | No, in the binary or the SDK | 0 hits for `opentelemetry`, `OTEL_`, `otlp` |

## Could not determine
- Real `ps` output. No running instance, so the `argv[0]` shape (`jules` versus a full path) comes from `run.cjs` (`spawn(binPath, ...)`, full path) and from how a shell launches it (bare name). The row matches on base name, so both work.
- Whether npm's bin symlink or the extracted Go binary ends up at `<prefix>/bin/jules`. The postinstall extracts `jules` and `run.cjs` into the same dir where npm links the bin. Either way the Go process is named `jules`; only the wrapper layer differs.
- Where the CLI keeps its OAuth token file (keyring first, "file fallback" second) and its `dotjules` config. `dotjules.DotJulesConfig` and `PrepareJulesDir` exist, but no path string was printed. Not recorded as a session store.
- The TUI's CPU when idle versus busy. `tree_cpu` 3 percent is a guess and says nothing about the cloud task.
- Whether the TUI can run anything locally. The binary contains `flow.RunShellAction`, `WriteFileAction`, `LocalExecutionResult`, a `local.StartDaemon` package and an `aida.googleapis.com/v1/swebot` URL, which looks like an earlier local-agent design. No command or docs page reaches it, so I could not tell whether it is live or dead code.
- The CLI's exact behaviour when a bare `jules` runs with piped input, and its full flag list beyond the docs.
- Cloud-side telemetry, and whether the private Jules backend has any per-session event stream beyond polling.

## Contradicts common belief or the obvious approach
- "Jules is a CLI agent" is wrong. Jules Tools is a remote control. Killing or idling the local process changes nothing about a running cloud session, and a session runs with no local process at all (web app, API, GitHub label, schedule, CI fixer).
- A detector cannot say "Jules is working" from the Mac. The probe finds only the client; its CPU is weak evidence about the client alone. The row says so.
- `--session` is not a session id flag. In `remote new` it is the task prompt. Setting `session_id_args: ["--session"]` (the usual pattern in other rows) would read the first word of a prompt as an id.
- The npm package is a launcher. `npm ls -g` shows a Node package, but the process is a Go binary; the `node` parent does not match and must not.
- `~/.jules` is not Jules Tools' session store. The only session files anywhere belong to the JS SDK and may sit in a project directory.
- No OpenTelemetry and no hooks, unlike most CLI agents in this registry. Docs use "web hook" only as an inbound trigger.
- `jules new "..."` (short form) is not in the CLI reference page but is in the binary's own help text.
- The Gemini CLI `/jules` extension runs inside a `gemini` process and shells out to the Jules CLI; the `gemini-cli` row owns it.

## Verification

Independent refutation pass, 2026-09-29. `tools/validate_row.py registry/agents/jules.json` printed `ok` before and after the repairs. Re-fetched npm `@google/jules` 0.1.42 and `@google/jules-sdk` 0.2.0 tarballs and the darwin_arm64 payload into scratch (never executed, nothing installed) and re-scraped the docs. Confidence stays `documented`: the harness is not installed here.

| Claim | Result | Basis |
|---|---|---|
| Cloud agent, each task in a fresh VM that clones the repo, notifications when a plan is ready or a task completes | confirmed | docs faq, re-scraped |
| CLI reference: `npm install -g @google/jules`; commands version, remote list/new/pull, completion, login, logout; bare `jules` opens the TUI | confirmed | https://jules.google/docs/cli/reference. Docs also list a global `--theme <string>` flag, which the row did not mention; it only affects the TUI and needs no matcher change |
| npm package is a 4-file launcher | confirmed | tarball holds README.md, index.cjs, package.json, run.cjs |
| Postinstall downloads the Go binary into the npm global bin dir; npx uses `$TMPDIR/jules_tmp/jules` | confirmed | index.cjs `getInstallationPath`, `BINARY_NAMES = [jules, run.cjs]`; run.cjs `installPath` |
| Under a global install there is a `node` parent plus a `jules` child | corrected to inferred | postinstall extracts both `jules` and `run.cjs` into the bin dir, and run.cjs only looks for `jules` in its own directory, so which of the two runs from `<prefix>/bin` was not observed. Row and source reworded; either shape matches only the Go process |
| Payload is a single Mach-O arm64 executable, Go 1.24.8, module jules-cli, ad-hoc signed, Identifier a.out, no Info.plist, v0.1.42 | corrected | `file`, `codesign -dv`, strings all match. The tarball also contains run.cjs, README.md and a licenses/ tree, so "single" was wrong; reworded |
| v0.1.42 is latest, dated 2025-12-16 | confirmed | `latest: v0.1.42` in metadata.yaml; npm dist-tag latest 0.1.42, time 2025-12-16 |
| Embedded help example `jules remote new --repo torvalds/linux --parallel 3 "write unit tests"` | corrected | That string is not in the binary. The binary has `jules new --repo torvalds/linux --parallel 3 "write unit tests"` and `jules remote new --repo jiahao42/jules-cli --session "..."`. The docs example is `remote new --repo torvalds/linux --session "write unit tests"`. Source quote fixed |
| Subcommands new, remote list/new/pull, teleport, login, logout; `--parallel` 1 to 5; `--session` is the prompt in `remote new` and the id in `remote pull` | confirmed | binary strings and CLI reference. So `session_id_args` correctly stays unset |
| No local sessions or transcripts from Jules Tools; token in keyring with file fallback; `dotjules` package; no `.jsonl` | confirmed | zero `.jsonl` hits in the binary; `saveTokenToFile`, `go-keyring-base64:`, `dotjules.*` symbols present. Token and config path still unknown, as the row says |
| Session states and activity types | confirmed | https://jules.google/docs/api/reference/types |
| SDK-only cache `<root>/.jules/cache/<sessionId>/activities.jsonl`, `metadata.json`, `sync-checkpoint.json`; root order JULES_HOME, cwd with package.json, HOME, TMPDIR | confirmed | `getRootDir()` in jules-sdk 0.2.0 `dist/index.mjs`. Each candidate must also be writable, and a `global-metadata.json` sits in `.jules/cache` too. `session_store.documented=false` is right |
| No lifecycle hooks in the docs | confirmed, count softened | 23 pages re-grepped (list in the source entry); only hits are 'useCache hook' (running-tasks) and 'failed web hook' (integrations). The earlier "29 pages" could not be reproduced (the sitemap URL now returns 404 for me), so the wording now says what I checked |
| No OpenTelemetry in the binary or SDK | confirmed | 0 hits for `opentelemetry`, `OTEL_`, `otlp` in both |
| Not installed or running here | confirmed | `which jules` printed `jules not found`; no /Applications hit; `ls ~/.jules ~/.config/jules` printed No such file; no jules in nvm bin dirs; `ps` showed only my own shell |
| Gemini CLI extension drives Jules through the Jules CLI; jules-action runs it in workflows | confirmed | extension README line 47 ('Gemini CLI will automatically install the Jules CLI'); jules-action page meta description |
| No first-party macOS app or bundle id | confirmed as far as found | docs re-grepped for macOS, desktop app, homebrew: no hit; a news search found no Jules desktop app |
| `names: ["jules"]` false positives | checked, one collision found and cleared | npm package `jules` 1.0.0 (2017, json tool) has bin `jules` -> `cli.js`, a node script, so argv[0] is `node` and it does not match. No Homebrew formula, no crates.io crate. PyPI `jules` is a 2012 blog generator, not checked for console scripts. A compiled `jules` from another vendor cannot be ruled out. New source entry added |
| Surface order and exclude_args | confirmed by reading `tools/agents_probe.py` | first matching surface wins. TUI excludes new/remote/teleport/login/logout/version/completion/help by exact argument. The one-shot surfaces use substring `args_contain`, so a `new` prompt containing "remote" is filed under `remote`; all three are one-shot, so the state is the same. Noted in row notes |
| `tree_cpu` floor 3 percent | unsupported (inferred) | already stated as a guess in the row; nothing measured |

Still unproven: the real `ps` argv shape of a global npm install, and the TUI's CPU when busy versus idle. Both need an installed harness.
