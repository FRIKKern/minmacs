# grok-bot: evidence notes

Row: `registry/agents/grok-bot.json`. Validator: `python3 tools/validate_row.py registry/agents/grok-bot.json` printed `ok`. Date 2026-09-30. Confidence `inferred`. Not installed here (`ls /Applications | grep -i -E 'grok|x\.ai|xai'` empty; `ls ~/.grok` no such directory). No binary was downloaded, nothing was run.

## Bottom line

Grok Bot is a client, not the agent. The Bots run on a Cursor-hosted Linux computer, one per user, shared by all their Bots. Closing the app or the laptop does not stop a turn (docs.x.ai/grok-bot/overview, computer-and-apps, troubleshooting). No process, child, CPU or file signal on the Mac can say "a turn is in progress". The row says so and lists the weak signals a Mac can see.

```
 Mac                                          Cursor cloud
 Grok Bot.app (Electron, com.anysphere.sand)  Bot turns, shell, browser, computer use
   renderer / helpers / coordinator           (the real work, no local trace)
   local-exec-daemon (detached, opt-in)  <--SSE-- /local-exec/requests
     bash -c per command  --> only local trace of a turn
   sand-client-persistence/*.blob (chat replica, lossy)
```

## What I checked

- Vendor docs, the Grok Bot pages listed in `https://docs.x.ai/llms.txt` (overview, get-started, bots, chat, files, computer-and-apps, skills, settings-and-notifications, approvals-security-and-privacy, teams-and-enterprises, computers, security, security-faq, troubleshooting, faq, proxies, private-networks, identity-and-access; mobile and use-cases not read). Grepped for hook, telemetry, otel, local computer, daemon, background.
- Homebrew cask `grok-bot` (0.63.0, autobump): `app "Grok Bot.app"`, zap paths naming `com.anysphere.sand` and `Grok Bot`. This is the only public source for the bundle id and app name that is not a blog.
- CASS source `franken_agent_detection/src/connectors/grok_bot.rs` and `lib.rs`: store path, filename encoding, JSON envelope, entry kinds, 200-entry cap. Printed key names only from the code, opened no real store (none exists here).
- Cursor OTel wire reference (`cursor.com/docs/enterprise/opentelemetry-export/wire`): transport, `cursor.surface=grok_bot`, `grok_bot_agent_actions` events, `tool_decision` outcomes, `hook` decision source.
- Third-party teardown of v0.18.0 (`shadown.github.io/blog/posts/2026-09-03_grok_bot_how-it-works/`): process layout, daemon, `~/.grokbot`, secrets store. Used for process and daemon claims only, marked `third-party`.
- Local match test, throwaway script (not saved): fed synthetic argv for the app, helpers, daemon, Grok Build and Cursor through `tools/agents_probe.py matches()` against all rows. Result: app -> `grok-bot` gui (score 38); renderer and utility helpers -> no match; daemon -> `grok-bot` daemon (39 or 53); `~/.grok/bin/grok` -> `grok-build` only; Cursor -> `cursor` only. No collision. The argv were invented from the teardown, so this proves the row's logic, not the real app.

## Answers by question

- Names and paths: `/Applications/Grok Bot.app/Contents/MacOS/Grok Bot`; helpers under `Contents/Frameworks/Grok Bot Helper*.app` (not matched on purpose). Bundle id `com.anysphere.sand`. Not `Cursor.app`: the `cursor` row matches `/Cursor.app/Contents/MacOS/Cursor` and does not touch this path.
- Process to session: no mapping exists. A "session" is a Bot conversation in the cloud. One app process serves every Bot. `session_id_args` omitted.
- Store: `~/Library/Application Support/Grok Bot/sand-client-persistence/<base32(key)>.blob`, JSON, `documented=false`. Per account and Bot, capped near 200 entries, chat only. Glob is narrowed to the base32 of `sand.client.slice.account.auth0`.
- Turn in progress: none reliable. Best available: `tool_children` on the daemon (local command running), `transcript_write` on the replica (app open only), CPU at the Electron floor.
- Waiting on the human: in-app only (sidebar "Needs attention", opt-in per-Bot OS notification). Enterprise OTel `tool_decision` records outcomes afterwards, not a live pending state.
- Hooks: docs never mention user hooks for Grok Bot. OTel names a `pre-tool hook` as a Grok Bot decision source, so something exists; config location unknown, and it would run in the cloud computer.
- OTel: yes, Enterprise only, exported by Cursor's backend to a customer collector (OTLP/HTTP protobuf, `<base>/v1/logs`, `/v1/metrics`). Action Recording must be on. No local exporter.

## Could not determine

- Real argv of the local-exec daemon, and whether the main process or the coordinator utility process spawns it. If the main process spawns it, the probe folds it into the app row while the app lives; if the utility process does, it appears on its own. The row covers both binaries but neither is confirmed.
- Everything about 0.63.0. The teardown is of 0.18.0; the cask is at 0.63.0 after roughly six weeks. Paths, the daemon, `~/.grokbot` and the replica schema may have moved.
- Whether the app holds a power assertion, or whether `~/.grokbot/local-exec-daemon.json` `inflightCount` still exists. It would be the best local signal for a local command in flight but is a JSON-field read the probe cannot do, and it is unverified.
- Whether the replica is rewritten during a cloud turn when the app is in the background. The only fixture is a user-reported sample, not a live capture.
- Whether the `.blob` directory holds other keys besides replicas and secrets. A detector must decode the filename and require `.transcript.replicas.` before opening any file.
- Bundle id of the iOS app and any Windows or Linux process names: out of scope for macOS.
- Grok Bot 0.63.0 login items or menu-bar helper: nothing found in docs.

## Contradicts common belief

- "Grok Bot" is not Grok Build. Different product, different store (`~/.grok`), different row. The `grok` CLI and Homebrew cask `grok-build` are the CLI.
- Not an xAI-built stack on the client: the download host is `downloads.cursor.com/sand/...` and `api2.cursor.sh`, sign-in is a Cursor account, privacy mode is Cursor's, telemetry is `service.name=cursor`. "xAI's desktop app" is true of the brand, not the infrastructure.
- "Working" cannot be read from the app. Unlike every CLI row, a live turn with the app closed leaves no local trace, and an idle-looking app may be driving a busy Bot.
- The CASS store name suggests chat history. It is a rolling window of about 200 entries with `history_complete: false`. It is not a transcript log.
- `sand-client-persistence` is not only chat: the teardown says it also holds Keychain-encrypted secrets. Treat the directory as sensitive; never read a blob whose decoded name is not a replica key.
- The docs claim "closing the app does not stop cloud work", yet the local-exec daemon is deliberately built to outlive the app (teardown). Local command work can therefore continue with the app quit, but only for commands the cloud Bot already sent and the user approved.

## Verification

Adversarial re-check, 2026-09-30. Validator `python3 tools/validate_row.py registry/agents/grok-bot.json` printed `ok` before and after the repair. Confidence moved from `inferred` to `documented`: the app surface now rests on the vendor's own 0.63.0 zip and app.asar, not only on the 0.18.0 blog. The harness is not installed here, so `verified-locally` is not available. Where the sections above disagree with this one (daemon detached and surviving quit, glob "narrowed to auth0", `tool_children`), this section wins.

Method for the shipped-bundle claims: `curl -sL https://api2.cursor.sh/updates/api/update/darwin-arm64/sand/0.0.0/stable` gave the 0.63.0 zip URL; I read the zip central directory and Info.plists with `curl -r` range requests, inflated only `Contents/Resources/app.asar` into the scratchpad, and grepped the minified bundles. Nothing was installed or run. Mock data only for synthetic argv tests.

```
 Grok Bot.app (main, argv[0] .../Contents/MacOS/Grok Bot)     <- the only process the row matches
   |-- Grok Bot Helper (Renderer)/(GPU)/(Plugin)               no match
   |-- Grok Bot Helper --type=utility  x2 (coordinator, local-exec daemon, both forked by main)   no match
   |     `-- bash -c <cmd>   (only while a local command runs)  grandchild of the app, so tool_children cannot see it
   `-- Contents/Helpers/Grok Bot Computer Use.app (CUGrokBotService)   no match
```

### Sources, one by one

| # | Claim | Result | Note |
|---|---|---|---|
| 0 | Launched 2026-08-11 on desktop and iOS; SuperGrok and Cursor plans; Bots keep working with the laptop closed | confirmed | x.ai/news dated Aug 11, 2026 says "available today ... on desktop and iOS", beta. docs.x.ai overview has the closing-the-app quote. Docs also list Windows, Linux, Android and iPad, which the row does not need. |
| 1 | One persistent cloud computer per user; cloud work continues when the app is closed | confirmed | Both quotes present on computer-and-apps and troubleshooting. |
| 2 | Cask `grok-bot` 0.63.0, `app "Grok Bot.app"`, dmg host, zap paths, auto_updates | confirmed | Cask commit dated Sep 30, 2026. The zip in the update feed lives under `/grokbot/stable/`, the dmg under `/sand/stable/`; both exist (dmg HEAD 200). Zap also lists Saved Application State. |
| 3 | Bundle id `com.anysphere.sand`, Electron 42.1.0, internal name sand | confirmed for 0.63.0 | Info.plist and Electron Framework plist read from the shipped zip. The teardown only covered 0.18.0; now it is re-checked. |
| 3 | Five processes, coordinator utility process, daemon "detached, run with ELECTRON_RUN_AS_NODE" | corrected | 0.63.0 forks the daemon as an Electron utility process from main (`serviceName: "sand-local-exec-daemon"`); `ine()` deletes `ELECTRON_RUN_AS_NODE`; the detached spawn only runs when `daemonEntryArgv` is passed, which app code never does. |
| 3 | Daemon writes `~/.grokbot/local-exec-daemon.json` with pid, startedAt, inflightCount; data root `~/.grokbot`; logs in `~/.grokbot/logs` | confirmed (code) | The record shape and file names are in the 0.63.0 code. The logs directory is only from the teardown. |
| 4 | Daemon pulls SSE from `/local-exec/requests`, bash -c per command, `localToolPermission` never/always/ask, default ask, `local-tool-approvals.json` | confirmed, extended | Paths, enum key and file name are in the 0.63.0 daemon bundle. Also present: `localToolPermissionCeiling` and `localToolPermissionByMachineId`. The 10 minute TTL is unsupported for 0.63.0 (not re-checked, removed from the claim). |
| 5 | Execution on Local Computer: Ask every time (default) / Always allow / Never allow; Bots run commands, read and move files through the desktop app | confirmed | approvals-security-and-privacy and security pages. The setting moves to per-computer under Settings > Computer > Computers once computers are registered; the row does not depend on that. |
| 6 | CASS store path, base32 file names, JSON envelope, entry kinds, 200 cap, belongs to account and agent | confirmed | Constants and tests in `grok_bot.rs` match. Strength stays third-party: one sanitised user-reported fixture, not a live capture. The 0.63.0 bundle does hold a `transcript.replicas` store slice under `userData/sand-client-persistence`, which corroborates the name but not the encoding. |
| 7 | The same directory holds encrypted secrets blobs | confirmed in part | Teardown (0.18.0) says so; the 0.63.0 client store is constructed with `setBoxSecrets`, consistent. Key names for secrets are unknown. |
| 8 | "Glob prefix is the base32 of the first 30 bytes of `sand.client.slice.account.auth0`" | corrected | The first 30 bytes are `sand.client.slice.account.auth` (26 + 4), no `0`; `b32decode` printed exactly that. The stated source string was 31 bytes long. Harmless in effect but wrong as written, and the old glob `<prefix>*.blob` would also match any other key that starts `...account.auth`, including secrets. |
| 9 | OTel: Enterprise only, backend sent, OTLP/HTTP protobuf, `cursor.surface=grok_bot`, Action Recording required, tool_decision source `hook`, outcomes held/timed_out | confirmed | Wire reference text matches. The "Enterprise only" part is on docs.x.ai (security, teams-and-enterprises), not on the wire page. |
| 10 | Waiting shown only in app: Needs attention, per-Bot OS notification | confirmed | settings-and-notifications: "Needs attention for a question, approval, or handoff"; notifications suppressed while focused. |
| 11 | Grok Build is a separate product with its own row | confirmed | docs.x.ai/build and `registry/agents/grok-build.json`. Probe test: no argv matched both rows. |
| 12 | Not installed here | confirmed | `ls /Applications \| grep -i -E 'grok\|x\.ai\|xai'` empty; `ls ~/.grok ~/.grokbot "$HOME/Library/Application Support/Grok Bot"` all "No such file or directory". No `Grok Bot` process in `ps`. |

### Row fields

| Field | Result | Note |
|---|---|---|
| `surfaces[0]` path `/Grok Bot.app/Contents/MacOS/Grok Bot` | confirmed | CFBundleExecutable is `Grok Bot`, bundle id `com.anysphere.sand`. Helper names `Grok Bot Helper`, `(Renderer)`, `(GPU)`, `(Plugin)` are real (zip listing) and none contain the path. A new helper appears in the 0.63.0 zip, `Contents/Helpers/Grok Bot Computer Use.app` (`CUGrokBotService`, bundle `co.anysphere.grok-bot-computer-use`); it does not match. |
| False positives of the app pattern | none found | Synthetic argv over every registry row: only the main binary matches (also a copy under ~/Downloads, which is fine). `bash -c 'echo local-exec-daemon Grok Bot'`, `vim local-exec-daemon.md`, helpers, computer-use helper: no row. Not real running processes. |
| `surfaces[1]` daemon "spawned detached, survives app quit, ELECTRON_RUN_AS_NODE" | corrected | 0.63.0: utility process forked by main; a normal quit runs `killLocalExecDaemon()`; only a restart-for-update keeps it. Its argv is expected to be the generic Helper utility argv without `local-exec-daemon`, so the row's match rule is expected to be inert. I kept it because it cannot false-positive, and said so in the label. Not verified against a live process. |
| `surfaces[1]` "when spawned by main the probe folds it into the app row" | confirmed as reasoning, now the normal case | Parent is main, which matches the app surface. |
| `working_signals` `tool_children` | unsupported, removed | The shells are children of the daemon utility process, never direct children of the matched main process, and the daemon is folded away anyway. Direct-children-only rule makes it unreachable. |
| `working_signals` `transcript_write` | unsupported as a probe signal, kept as a host signal | The file is not mappable to a process; the row already said that. It raises working only while the app is open. Nothing here was observed live. |
| `working_signals` `tree_cpu` floor 10 | inferred | Electron floor from the README defaults, no measurement. Now says local commands do show up in tree CPU because the daemon and its shells are descendants of main. |
| `session_store.glob` | corrected | Now pins the replica suffix. The key is 65 bytes before `.transcript.replicas.` and 65 is a multiple of 5, so the base32 of `.transcript.replicas` is a fixed 32-character block after 56 ULID-dependent characters. fnmatch check: CASS fixture key True, second ULID-shaped key True, `.secrets` and `.send-journal` keys False. Assumes a 26-character ULID subject like CASS. |
| `session_store.documented=false`, `format=json` | confirmed | Undocumented by the vendor; format from CASS. |
| `hooks.supported=true`, event `pre_tool_use` | weakly supported, wording corrected | docs.x.ai names "a hook" as a decider; OTel has `decision.source=hook`; bundle has `team.hooks.read/manage` permission ids. No config location, no event list beyond the pre-tool decision. |
| `waiting_signals` (ui, os_notification, otel) | confirmed | Same sources as #9 and #10. `otel` is after-the-fact. |
| `telemetry.otel=true` | confirmed | Enterprise only, backend side. |
| `vendor` "SpaceXAI (xAI), built on Cursor (Anysphere)" | confirmed | package.json author `SpaceXAI`, homepage cursor.com, npm scopes `@anysphere/*`, docs are on docs.x.ai, sign-in is a Cursor account. |
| Power assertion | none found | `powerSaveBlocker` and `caffeinate` occur 0 times in the main bundles, so no `power_assertion` signal exists. |

### Still unsupported or open

- Real argv of a running Grok Bot (main and utility helpers): never seen live. The row's app rule follows from the Info.plist and Electron's standard argv[0], not from `ps`.
- Whether Electron exposes `serviceName` in the utility process argv. Chromium normally does not; unverified, so the daemon rule stays as an inert catch-all.
- Whether the restart-for-update daemon leftover appears as an orphan and what its argv is.
- The 0.63.0 replica file encoding and the `~/Library/Application Support/Grok Bot` path in practice (Electron `userData` default plus the Homebrew zap; `--user-data-dir` overrides it).
- The 10 minute approval TTL and the daemon log location under 0.63.0.
- Windows and Linux process names: out of scope.
