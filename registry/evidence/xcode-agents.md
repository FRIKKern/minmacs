# Xcode coding agents: evidence notes (2026-09-29)

Not installed here. Xcode is absent (only Command Line Tools), so this row is `inferred`: Apple docs plus third-party reports, no running instance.

## Shape

```
Xcode.app (com.apple.dt.Xcode)          one process, holds every conversation
  '- runs agents it downloaded itself, under
     ~/Library/Developer/Xcode/CodingAssistant/
       Agents/claude/<ver>/claude        real Claude Code binary (26.3 RC: Agents/Versions/26.3/claude)
       Agents/.../codex                  upstream Codex binary (26.3 shipped 0.98.0)
       Agents/.../gemini                 Gemini CLI (26.6 and 27), layout unknown
       ClaudeAgentConfig/  = CLAUDE_CONFIG_DIR   settings.json, .claude.json, skills/, commands/, debug/, projects/*.jsonl
       codex/              config.toml, auth.json, skills/, sessions/  (CODEX_HOME, inferred)
       gemini/             config folder (Apple docs)
  '- ACP agents (26.6, 27): any binary the user typed, e.g. `copilot --acp`
external claude/codex the user runs in a terminal  -> reach Xcode through `xcrun mcpbridge`
```

## What I checked

- Local, read-only: `ls /Applications`, `xcode-select -p`, `xcodebuild -version`, `xcrun --find mcpbridge`, `ls ~/Library/Developer/Xcode`, `ps`. Xcode not installed; no `CodingAssistant` folder; no Xcode process. The `~/Library/Developer/Xcode` there (DerivedData, UserData) dates from Dec 2025, before agents existed.
- Apple docs, fetched: setting-up-coding-intelligence, extending-and-customizing-agents, writing-code-with-intelligence-in-xcode, giving-external-agents-access-to-xcode, Xcode 26.3 and 27 release notes.
- Anthropic: "Apple's Xcode now supports the Claude Agent SDK" (Feb 3 2026).
- Third-party for the parts Apple does not document: Apple Developer Forums (Agents/claude/*/claude), fatbobman (CLAUDE_CONFIG_DIR, 26.3 RC layout), Jack Pearce (strings on the bundled binary), a gist on third-party endpoints (debug folder, settings.json env), Codex/Gemini upstream hook docs.
- Public source: `phuryn/claude-usage` scanner.py reads `.../ClaudeAgentConfig/projects`; `stevencarpenter/hippo` config lists `.../codex/sessions`.
- Row validated with `tools/validate_row.py`; process rules run on 10 synthetic argv lines through `agents_probe.matches()`; `agents_probe.py --row` reports 0 sessions.

## Could not determine

- **The real `ps` line** of any Xcode agent: argv[0] (absolute path vs bare name), arguments, whether Claude gets `--session-id` or `--resume`, whether Codex runs as `app-server` (inferred from Codex 0.98 and from how rich clients use it) or as an ACP wrapper. Process rules rest on the folder layout only.
- **Gemini**: executable name, native vs node script, chat storage.
- **Xcode's own conversation store** (sidebar, History slider, rollback): no path or format found anywhere.
- **Whether a turn holds any power assertion** (Xcode or agent). Codex's is off by default; nothing known for Xcode.
- **Whether `caffeinate` appears** under Xcode's headless claude. Weak lean: no, since the sleep-inhibitor strings sit beside interactive-UI strings in the binary (local `strings` on 2.1.283). Not tested; running claude here was out of bounds.
- **Whether hooks run**: Claude probably (settings.json env is honoured), Codex probably not for user hooks (trust review needs a UI Xcode lacks). Both untested.
- OTel: only inherited settings, not tested. Apple's release notes mention a provider telemetry toggle with no detail.
- Exact Xcode 27 ship date and whether 27.0 and 26.6 differ in layout; `xcrun mcp-server` (27 beta 5) not examined.

## Against common belief

1. **Xcode's agent is not your `claude`/`codex`.** It is a separate download, a separate config dir and, per third-party posts, a restricted environment that ignores `~/.claude`, `~/.codex` and the shell profile. Sessions do not show up in `~/.claude/projects`.
2. **Two very different things share the words "agents in Xcode".** Agents Xcode hosts (this row) versus agents you launch in Terminal that call Xcode through `xcrun mcpbridge`. The second are ordinary claude/codex processes; `mcpbridge` is a child of them, not an agent.
3. **The obvious detector double-counts.** Matching by name `claude` (claude-code row) or `codex app-server` (codex row) also hits these binaries, verified with synthetic argv. A path under `/Xcode/CodingAssistant/Agents/` is the only discriminator, and it must win.
4. **The best "working" signal is not in the process table.** Apple's own indicator is the Assistant Activity toolbar button (spins, and shows a warning icon when Xcode needs the human). Readable only through accessibility. One Xcode process serves all conversations, so CPU or children of Xcode say nothing per agent.
5. **The terminal signal may not exist.** The claude-code row's `caffeinate` child is proven for the terminal UI; Xcode runs the same binary without that UI.
6. **Codex hooks may be silent no-ops.** Non-managed Codex hooks stay skipped until trusted in the terminal UI; Xcode has none.
7. **A `ClaudeAgent` process name** appears in one Medium how-to (`killall -9 ClaudeAgent`) and nowhere else. Not used. Treat as unverified, possibly wrong.
8. **ACP agents in Xcode are invisible as Xcode's** on a command line. They match their own harness row; only the parent (Xcode) gives them away, and the registry has no ancestor rule.
9. **Intel Macs cannot run these agents** as shipped (arm64 only, forum post), which shows up as a process that dies at launch, not as an error.

## Verification

Independent check, 2026-09-29. Confidence stays `inferred`: no Xcode agent process was ever observed and this harness is not installed here, so `documented` at most for the folder and product facts, and nothing about the process shape rises above inference. `tools/validate_row.py` passes before and after.

### Claims

| Claim | Result | Basis |
|---|---|---|
| 26.3 added Claude Agent and Codex, permissions system, one-click install, auto-update | confirmed | 26.3 release notes; Tech Talk 111428 ("download ... with just a click, and they update automatically"); setting-up-coding-intelligence page |
| Xcode 27 adds Gemini, ACP, plug-ins with skills, MCP servers, ACP configs | confirmed | 27 release notes, exact lines. Corrected: 26.6 release notes already list Gemini and ACP; `xcrun mcp-server` is a Beta 5 preview, enabled with `sudo xcrun mcp-server enable` |
| Config folders `ClaudeAgentConfig`, `codex`, `gemini`, used exclusively by Xcode; Add an Agent (ACP); downloads managed as components | confirmed | extending-and-customizing-agents; setting-up-coding-intelligence; forum 837540 reply names Settings > Components (third party) |
| Assistant Activity button spins, stops, warning icon | confirmed | writing-code-with-intelligence-in-xcode, text matches |
| External agents use `xcrun mcpbridge` | confirmed | giving-external-agents-access-to-xcode (`claude mcp add ... -- xcrun mcpbridge`) |
| Claude Agent is Claude Code's harness | confirmed, wording softened | Anthropic post: "the same underlying harness that powers Claude Code" via the Agent SDK. "Real Claude Code native binary" is stronger than the post; the two blogs (env vars accepted, `CLAUDE_CONFIG_DIR`) support it indirectly |
| 26.3 RC path `Agents/Versions/26.3/claude` | corrected | Both blogs give `.../Agents/Versions/26.3` as the executable; neither says `/claude` follows. Row no longer claims it, and no longer matches it on the Claude surface |
| Later layout `Agents/claude/<ver>/claude`, Info.plist beside it, arm64 only | confirmed, one part dropped | Forum 840995 excerpt (tag page; the thread page itself sits behind a bot check). Corrected: the post does not say "Xcode 26.5 and later". Unsupported and removed: "Codex is the upstream `codex-<arch>-apple-darwin` release" |
| `ClaudeAgentConfig` is Claude's config dir, restricted environment | confirmed, partly corrected | fatbobman (`CLAUDE_CONFIG_DIR`, restricted environment), gist (`settings.json`, `debug/`), giginet README (`.claude.json`). Corrected: the gist sets `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_BASE_URL`; `CLAUDE_CODE_OAUTH_TOKEN` comes from the forum excerpt. `skills/` and `commands/` there: unsupported by anything read |
| Claude transcripts under `ClaudeAgentConfig/projects/` | corrected | scanner.py line 21 confirmed; it globs `**/*.jsonl` (line 593), so the `projects/*/*.jsonl` depth is inferred, and a scanner path is not proof Xcode writes there |
| Codex sessions under `codex/sessions` | corrected | hippo line 240 is a comment documenting a default, not code. giginet README confirms `codex` is `CODEX_HOME`, so the path follows from that. Still `documented: false`, not on disk |
| 26.3 shipped Codex 0.98.0 | confirmed | Listed among fixes in the 26.3 notes. That Xcode runs it as `app-server` remains inferred |
| Codex hooks: twelve events, PermissionRequest, trust review; Gemini hooks in `settings.json` with `Notification`/`ToolPermission` | confirmed | learn.chatgpt.com/docs/hooks (12 counted; `/hooks` trust UI; `--dangerously-bypass-hook-trust`); geminicli.com hooks reference. "Xcode has no trust UI" is inference |
| Gemini CLI 0.42.0 | confirmed (third party) | Forum excerpt: "Xcode currently uses Gemini CLI v0.42.0". Executable name and layout unknown |
| Bundle id `com.apple.dt.Xcode` | corrected | Had no source. Apple's MDM docs name `com.apple.dt.Xcode` as the PayloadType; bundle id equals it by convention, not checked (Xcode absent) |
| Xcode absent locally | confirmed | Re-ran: no `Xcode*` in `/Applications`, `xcode-select -p` is CommandLineTools, `xcrun --find mcpbridge` fails, no `CodingAssistant` folder, no Xcode process. Error strings in the row corrected to the exact text |
| claude-code `tui` surface also matches the Xcode binary | confirmed | Re-ran `matches()` with a synthetic argv |
| No `ps` line, `--session-id`, `app-server` shape, `caffeinate`, hooks running, CPU floor | unsupported (all inferred) | Stated as inferred in the row. `session_id_args` on the Claude surface is copied from claude-code, not observed |
| "Sleep-inhibitor strings sit in the interactive UI part, so caffeinate may never appear" (evidence file, row) | unsupported | Could not reproduce. In 2.1.284 `strings` shows a method that builds `["caffeinate",["-i","-t",n]]` on macOS with no visible link to a UI. Row now says unknown; the "Weak lean: no" under Could not determine above should be read as withdrawn |

### Process patterns

Run through `agents_probe.matches()` with synthetic argv.

- **False positive, fixed.** The old Claude surface required an argument containing `/claude`. A Codex (`codex --cd /Users/x/claude-proj`) or Gemini process under `Agents/` with such a path matched as Claude Agent. It now matches on `path_contains: /Xcode/CodingAssistant/Agents/claude/` alone, and those two land on the last surface.
- **False positive, fixed.** `claude --bg-pty-host` (a helper the claude-code row already excludes) matched as a session. Helper flags are now excluded on the Claude surface and on the last surface, otherwise it would fall through to it. `daemon` and `proxy` are excluded on the Codex surface and the last one, as in the codex row.
- **Still no match, as intended.** `~/.local/bin/claude`, the Xcode host process, and `ClaudeAgentConfig/claude` (capitalised, different folder).
- **Known false-positive risk, kept.** The last surface matches any binary under `Agents/`, so an unknown helper there would read as an idle agent. It is also the only thing that catches the `Agents/Versions/26.3` layout and Gemini, so it stays.
- **Not a false positive.** Overlap with claude-code and codex rows is real and documented in the row's notes; the probe does not deduplicate across rows.
- **Untested against a real process.** argv[0] may be a bare name, in which case every Agents-path rule misses.
