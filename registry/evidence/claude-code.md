# Claude Code

The worked example. Written by hand before the research storm, then corrected from the storm's critic.

## What was checked

- **Sleep inhibitor.** The binary contains the strings `caffeinate`, `-i`, `-t`, "Started ... to prevent sleep" and "Stopped sleep inhibitor, allowing sleep". `ps` shows `caffeinate -i -t 300` as a direct child of busy sessions only.
- **Separation.** On 2026-09-29, with 8 to 10 sessions open: working sessions held the child and ran at 9 to 11% CPU, idle ones had no child and stayed under 1%. One working session showed 2.6% CPU, so CPU alone would have called it idle.
- **Terminal title.** The hosts study found the title's busy glyph agreed with the caffeinate child in 7 of 7 sessions.
- **Agreement.** `minmacs agents` and `tools/agents_probe.py` report the same state for every session decided by the child signal.

## Corrections from the critic

- The path prefix `/.local/bin/claude` also matched `~/.local/bin/claude-swap`. Removed; the name `claude` covers the real binary.
- The VS Code extension's binary was being labelled a terminal session. It has its own `ide` surface now.
- `--bg-pty-host` and `--bg-spare` are helper processes, not sessions. Both flag spellings are excluded.

## Not verified

- The `ide` surface has not been seen running on this Mac.
- The desktop app surface is decided by CPU alone, since its launcher has no session id in its arguments.
- Headless runs (`claude -p`) and SDK use are not modelled.
