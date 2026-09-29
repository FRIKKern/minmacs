# Auggie (Augment Code) evidence notes (2026-09-29)

Not installed on this Mac (no `auggie`, no `~/.augment`, no app, no extension, no process). Nothing below was seen on a running instance. Confidence is `documented`. Sources: docs.augmentcode.com (pages fetched as `.md`), the published npm bundles unpacked in the scratchpad (nothing installed), the Augment VS Code extension VSIX unpacked the same way, and the public GitHub repos. Downloading and unpacking tarballs is the only thing done beyond reading.

## Shape

```
npm latest 0.36.0            node <prefix>/bin/auggie            (bin -> augment.mjs, Ink TUI)
npm preview/daemon 1.2.0-pre node <prefix>/bin/auggie            (bin -> auggie-v2.mjs, pi-mono fork)
  |- <shell> -c <cmd>         DIRECT child per shell-tool call, detached (own process group)
  |- MCP stdio servers        long-lived direct children (a /bin/sh -c one if useShellInterpolation)
  '- osascript (via sh)       sub-second, only with notificationMode = desktop_notification

auggie daemon                 not matched
  '- node augment.mjs cloud run-as-agent <agentId> --workspace .. --parent-daemon-id ..   matched, one per session
editor / VS Code sidecar  ->  node auggie --acp [--workspace-root ..]                     matched (kind ide)
other agent (Claude Code, Cursor) -> node auggie --mcp                                    NOT matched: helper, not a session
```

## What I checked

- Official docs: cli/overview, reference, hooks, config, autoupgrade, install, acp/agent, interactive, permissions, cloud, cosmos/environments/daemons and daemon-config, troubleshooting/logs and request-id, llms.txt index, and CHANGELOG.md from the GitHub repo.
- npm registry JSON for `@augmentcode/auggie`: dist-tags, bin, engines, optional dependency `node-pty`, file lists.
- Both bundles searched with grep and small Python scripts (they are not minified beyond identifier mangling): session store paths and writer, shell tool spawn, daemon child spawn, hooks schema and call sites, notification code, terminal title code, sleep-inhibitor strings, OTel code.
- The Augment VS Code extension (marketplace `augment.vscode-augment`, 0.901.1): how it launches an agent process.
- `tools/validate_row.py` passes. `tools/agents_probe.py --row` runs (0 sessions, as expected). I fed `matches()` fourteen synthetic argv strings: shim launch, `--resume <id>` (id parsed), direct package path, `--print`, `--acp`, daemon child, and the negatives (`daemon`, `--mcp`, `pi`, an unrelated `vim auggie`). All behave as the row intends.
- Local: `which auggie augment`, `ls -d ~/.augment`, `ls /Applications`, `ls ~/.vscode/extensions ~/.cursor/extensions`, `ps` all empty.

## Findings that shape the row

- Two generations share the name. `latest` is 0.36.0 (2026-08-21); all 74 versions starting with 1. are prereleases; the `preview` and `daemon` tags point at 1.2.0-prerelease.202609281519. The docs already say "Auggie 1.x uses the rebuilt agent harness" and tell daemon hosts to install `@augmentcode/auggie@daemon`. The row matches both by path shape.
- 1.x is a pi-mono fork: package description "Coding agent CLI with read, bash, edit, write tools and session management", theme `$schema` on `badlogic/pi-mono`, `https://pi.dev/session/`, JSONL header `{type:"session", version, id, timestamp, cwd}`. Same store idea as the `pi` row, different root.
- Session store 0.x: `~/.augment/sessions/<sessionId>.json`, whole-file atomic rewrite, saved per committed exchange and at loop end, error and interrupt. Key names come from the writer code, not from a file.
- Session store 1.x: `~/.augment/sessions-v2/--<cwd slug>--/<sessionId>.jsonl`, nothing written until the first assistant message ends.
- Process to session: no `--session-id` flag in either line; a fresh session has no id in argv; `--resume [id]` is the only id flag (`--session <path>` in 1.x takes a file). But 0.x writes `terminalId` (the output of `tty`) into every session file, so controlling tty from `ps` maps to a session. Newest file wins when several sessions used one tty.
- Working signal: direct shell child while a tool runs (detached `<shell> -c`, both lines). Blind during model streaming. Session-file mtime is a second raise-only signal. No sleep inhibitor anywhere (zero hits for caffeinate, pmset, IOPM, powerSaveBlocker in both bundles).
- Waiting: only through user-enabled notifications (`osascript` child with "Agent needs your input", or a BEL on the tty). Not distinguishable from completion for the bell.
- Hooks: `settings.json` in four locations, `command` type only, `.sh/.ps1/.cmd/.bat` scripts. Docs list five events; the schema accepts seven.
- OTel: real OTLP export only in 1.x, opt-in.
- Daemon: children are `cloud run-as-agent`; the row matches children and skips the parent so each session is judged on its own direct children.

## Could not determine

- Real `ps` output on a Mac. `node <prefix>/bin/auggie` for shim launches is inferred from the env-shebang first line of `augment.mjs`. No live process, so no CPU numbers either; `tree_cpu` at 3 percent is a guess.
- Whether 1.x prints a different argv (for example a re-exec). No sign of one in `auggie-v2.mjs`; 0.x has none either.
- Default of `notificationMode` on a fresh install. Docs list Off/Bell/Desktop; the wizard store starts at "off"; `--no-bell` implies bell may be default in some paths.
- Whether 1.x fires `PromptSubmit`, `Stop` and `Notification` the way 0.x does. Only the config schema was read.
- Whether the Augment extension's in-IDE agent ever exposes a process. Only the `--acp` sidecar and a one-shot migration engine were found.
- JetBrains plugin process shape. Not inspected.
- Whether `-p` runs register in the session store; `--print` and `-p` are treated the same, but `-p` cannot be matched because `args_contain` is a substring test ("-p" is inside "--mcp-config").
- Log file as a signal: `$TMPDIR/augment-log.txt` exists and is shared by all processes unless `--log-file` is passed. What it logs per turn was not checked.

## Contradicts common belief or the obvious approach

- "Auggie is open source on GitHub." `github.com/augmentcode/auggie` holds docs, example commands, a plugin marketplace and the changelog. The CLI source is not there; the published npm bundle is the only source.
- "Auggie 1.0 is out." Not as a stable release. Only prerelease tags, though the docs speak of 1.x as current.
- Docs say Node 20+; the repo README badge says Node 22+; 0.36.0 `engines` says `>=20.0.0`, 1.x says `>=20.6.0`.
- The hooks page lists five events. The code has seven, and the one that best marks a turn start (`PromptSubmit`) is the undocumented one. `Notification` is in the docs' field list and the schema but nothing fires it in 0.36.0, so a wait hook is a dead end.
- The terminal title does not show state. Unlike Claude Code or Gemini CLI, it is the conversation title cut to 15 characters, or "auggie". `--no-update-terminal-title` turns it off.
- The bundled OpenTelemetry packages in 0.36.0 look like telemetry support but are Sentry's instrumentation. No exporter. Real OTLP export exists only in 1.x and answers to `CLAUDE_CODE_ENABLE_TELEMETRY` as well as `AUGGIE_ENABLE_TELEMETRY`.
- `auggie --mcp` (the Context Engine MCP server that Claude Code, Cursor and others launch) is a long-lived `node .../auggie` process that looks like a session and is not one. The row vetoes it by exact argument.
- The sessions are not append logs in 0.x: each save rewrites the whole JSON, and `-backup<N>.json` files sit in the same folder and match the naive glob.
- Auggie reads Claude Code layouts: `~/.claude/commands`, `.claude/skills`, `CLAUDE.md`, `AGENTS.md`. Config directories alone do not say which of the two ran.
- It sets `AUGMENT_AGENT=1` for shells it starts, so a child shell can be told from a user's shell by environment, not by name.
- `ps` args are split on spaces, so exact-argument vetoes on ordinary words (`list`, `model`, `login`) drop sessions started with a prompt. I kept only `daemon` and `cloud` (plus the flags). A prompt containing those words as separate words is still dropped.

## Other Augment surfaces not covered

- Augment extension for VS Code (`augment.vscode-augment`) and JetBrains: the agent panel runs in the IDE, no matchable process.
- Cosmos (web app, cloud VMs, self-hosted daemons): cloud only, plus the daemon children above.
- Intent (intentapp.dev, `intent-hq/intent`, releases at `intent-hq/cloudlands-releases`, latest v2.182.0 with an arm64 macOS dmg/zip; Electron front end plus a Rust daemon `intentd`): a separate macOS desktop app that orchestrates Augment, Claude Code, Codex and OpenCode. It is a host or a harness in its own right and deserves its own row. Bundle id and process names not determined (app not downloaded).

## Verification

```
python3 tools/validate_row.py registry/agents/auggie.json      -> ok
python3 tools/agents_probe.py --row registry/agents/auggie.json -> 0 agent sessions (nothing running)
```

## Verification

Second pass, 2026-09-29, by a reviewer who did not write the row. Method: `tools/validate_row.py` (ok before and after), fresh downloads of `auggie-0.36.0.tgz`, `auggie-1.2.0-prerelease.202609281519.tgz` and the Augment VS Code VSIX 0.901.1 (unpacked in the scratchpad, nothing installed), the docs pages re-fetched as `.md`, npm registry JSON re-read, the GitHub repo page re-read, and synthetic argv fed to `agents_probe.matches()` for 21 shapes. Local state re-checked: no `auggie`/`augment` binary, no `~/.augment`, nothing in `/Applications` or the VS Code and Cursor extension folders, no matching process. Confidence stays `documented` (maximum, harness not installed). Nothing here was seen on a running instance.

Confirmed
- Install `npm install -g @augmentcode/auggie`, Node 20+, macOS/WSL/Linux, `--print` one-shot, interactive TUI (install page, overview, reference).
- npm dist-tags: latest 0.36.0 (2026-08-21), daemon and preview 1.2.0-prerelease.202609281519, prerelease 0.37.0-prerelease.202609282301. 74 versions start with `1.`, none without a prerelease suffix. `bin.auggie` is `augment.mjs` (0.36.0) and `auggie-v2.mjs` (1.x); engines `>=20.0.0` and `>=20.6.0`; optional dependency node-pty.
- Docs call 1.x "the rebuilt agent harness" and tell daemon hosts to run `npm install -g @augmentcode/auggie@daemon`.
- github.com/augmentcode/auggie holds only `.augment-plugin`, `.augment/commands`, `.github`, `examples`, `plugin_marketplace`, docs files and CHANGELOG (latest commit "docs: update changelog for v0.36.0"); README badge says Node 22+.
- 1.x is a pi-mono fork: description "Coding agent CLI with read, bash, edit, write tools and session management", `badlogic/pi-mono` theme schema URL, `https://pi.dev/session/`.
- 0.x session store `<cacheDir>/sessions/<id>.json`, saved by `saveSession`; `terminalId` comes from `tty` (`L9e`). 1.x store `sessions-v2/--<cwd slug>--/<id>.jsonl`. `--augment-cache-dir` moves the root.
- Session flags in docs (`--continue/-c`, `--resume/-r [id]`, `--dont-save-session`); 1.x usage text adds `--session <path>`, `--fork`, `--session-dir`. No `--session-id` flag in either.
- Log files `$TMPDIR/augment-log.txt` and `augment-daemon.txt` (docs and `Mye`/`hWr` constants).
- No `caffeinate`, `pmset`, `IOPM`, `powerSaveBlocker` in either bundle (0 hits each).
- Shell tool: 0.x `spawn(cmd, [], {shell, detached})`; 1.x `spawn(shell, ["-c", cmd], {detached:true})` with `/bin/bash` first on macOS. A shell is a direct child of the session process in both.
- Hooks: five events documented, seven in the 0.36.0 config schema, `PromptSubmit` fires from the send path, `Notification` has a definition and a no-op stub only, `command` type only, `.sh/.ps1/.cmd/.bat`, timeout default 60000 ms, settings locations and precedence, `agent_stop_cause` values.
- Notifications: modes off, bell, desktop_notification; macOS desktop mode builds `osascript -e 'display notification ...'` with "Agent needs your input" and "Agent response complete"; CHANGELOG lines on the terminal bell.
- OTel: 1.x `otel` extension with `AUGGIE_ENABLE_TELEMETRY`, alias `CLAUDE_CODE_ENABLE_TELEMETRY`, default off; 0.36.0 has no `OTEL_EXPORTER_OTLP` string.
- ACP: `auggie --acp`, docs list Zed, Neovim, Emacs. VS Code extension `augment.vscode-augment` 0.901.1 spawns `auggie --acp --workspace-root <dir> [--model m]` over stdio and ships `out/migration-engine/auggie-v2.mjs`. That engine is run with the host's `process.execPath` (an Electron helper inside VS Code), so it should not carry the process name `node` (inferred) and is not matched.
- `auggie --mcp` is documented as an MCP tool server (reference, "MCP Server Mode"); it is vetoed by exact argument.
- `indexing-worker.mjs` is a worker thread, not a process.

Corrected
- Daemon child argv on 1.x. The row matched only `cloud run-as-agent`, which is the 0.x form. In 1.x the daemon runs `<node> <entry> [--augment-*] --cloud-agent <agentId> --workspace-root <dir> --parent-daemon-id <vmId> ...` (auggie-v2.mjs `y.push("--cloud-agent",t,"--workspace-root",m,"--parent-daemon-id",...)`). Before the fix a 1.x daemon child was missed by the daemon surface and picked up as a plain `tui` session by the package-path surface, because the vetoed word `cloud` is absent. Added a second daemon surface on `--cloud-agent`, and added `--cloud-agent`, `--parent-daemon-id` and `--mode` to the exact-argument vetoes of the two interactive surfaces so the surfaces no longer depend on order.
- 1.x `--mode rpc|json|acp` exists and 1.x has no `--mcp`. `--mode` is now vetoed on the interactive surfaces (rpc and acp are host-driven helpers). `--mode acp` is not matched by the ACP surface, stated in its label.
- False-positive width of `--acp` and `--print`. They required only the substring `auggie` anywhere in argv, so `node /x/auggie-notes/server.js --acp` or `... build.js --print` matched. Each is now two surfaces requiring `bin/auggie` or `@augmentcode/auggie/` plus the flag. Residual: a program at a path ending in `bin/auggie<anything>` would still match; none is known.
- "It sets `AUGMENT_AGENT=1` for shells it starts" (Findings section above) holds for 0.x only (exec tool config `env:{AUGMENT_AGENT:"1"}`); the 1.x bundle has no such string.
- "Terminal title is the conversation title cut to 15 characters": it is shortened to at most 15 characters (at a word boundary or with a trailing ellipsis); "New Chat" and empty give `auggie`.
- Session file key names were incomplete. The writer also emits optional `subAgents`, `poseidonAgentId`, `parentConversationId`, `isCloudAgent` and `queue`. `terminalId` is only refreshed when stdin is a tty, so daemon children and piped print runs have none; `--resume` accepts an id prefix, so an argv id may not equal the file name.
- In 1.x `--resume/-r` is a picker flag ("Select a session to resume"), so `session_id_args: --resume` can read a prompt word as an id there. Harmless (the 0.x path is not found) and noted in the store entry.
- `tree_cpu` meaning now carries the indexing risk: both lines index the workspace inside the session process.

Unsupported (kept, flagged as unmeasured or inferred)
- `node <prefix>/bin/auggie` as the shim shape in `ps`. Inferred from the `#!/usr/bin/env node` first line; no live process seen. Correct for how macOS passes a script path, but not observed.
- `tree_cpu` floor of 3 percent. A guess, no measurement.
- `-p` runs. Not matchable (substring test), so they are invisible. Known gap, stated in the print surface label.
- 1.x firing of `PromptSubmit`, `Stop`, `Notification`, and whether `--enable-terminal` leaves a persistent shell child: not traced.
- Default `notificationMode` on a fresh install, JetBrains plugin process shape, the Intent app: not determined.
- Everything under "Not installed on this Mac" is only as good as today's `which`, `ls` and `ps`; it says nothing about other machines.
