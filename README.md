<p align="center"><img src="docs/app-icon.png" width="128" alt="MinMacs icon"></p>

# MinMacs

Reclaim your Mac for developers and agents. A free menu bar app that shows exactly what is burning CPU and memory, and quits the apps that do nothing for your work, in one click, gracefully, with a Restore button. Made for MacBooks that run Claude Code, builds, and long agent sessions next to a browser with a hundred tabs.

Part of a family: [Insomnia](https://github.com/FRIKKern/insomnia) keeps the Mac awake, [noo-noo](https://github.com/FRIKKern/noo-noo) keeps the disk clean, MinMacs keeps the CPU and RAM for what matters.

## The three rules

1. **Nothing is closed that wasn't shown first.** The menu is the plan. "Will close (4)" lists each app with its CPU and memory before you press anything.
2. **Only apps on an explicit close list get closed.** Developer and agent essentials, such as terminals, editors, Docker, databases, Claude, Insomnia and noo-noo, are on a keep list and never even offered. Anything unknown is listed as unsorted and never touched until you sort it, one click, remembered.
3. **Graceful quit only.** Apps get a normal Quit, never a force kill, so unsaved work asks first instead of vanishing. Browsers reopen their tabs. **Restore** relaunches everything MinMacs closed.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/FRIKKern/minmacs/main/install.sh | sh
```

Builds from source in a few seconds with Apple's Command Line Tools, so there is no Gatekeeper prompt. Installs `~/Applications/MinMacs.app` and a `minmacs` command in `~/.local/bin`. Or `brew install frikkern/tap/minmacs`, or the zip on the [latest release](https://github.com/FRIKKern/minmacs/releases/latest) (needs a right-click → Open once).

Options through the pipe: `MINMACS_LOGIN=1` registers Launch at Login, `MINMACS_NO_LAUNCH=1` installs only, `MINMACS_REF=v1.0.0` pins a tag. Uninstall with `curl -fsSL https://raw.githubusercontent.com/FRIKKern/minmacs/main/uninstall.sh | sh`.

Requirements: macOS 13 or newer, Apple Silicon or Intel.

## Use

Click the gauge in the menu bar:

```
41 apps · system load 63% · thermal nominal
──
⚡ MinMacs Now: close 2 apps (21% CPU · 9.4 GB)
   Restore 2 closed apps
──
Will close (2)
   Google Chrome      21% · 8.7 GB    ▸ Close on MinMacs / Keep / Unsorted / Quit Now
   Spotify             1% · 578 MB
Unsorted, not touched (3)
   FigmaAgent          0% · 13 MB     ▸ …
Kept, essentials (4)                  ▸ cmux 44% · 6.8 GB, Finder, Insomnia …
Background load (system, informational) ▸ top processes not owned by any app
──
✓ Ask Before Closing
✓ Also Turn On Insomnia
  Edit Rules…
  Launch at Login
──
  Quit MinMacs
```

- **MinMacs Now** shows a confirmation listing exactly what will quit, with a "Don't ask again" box. Then it quits them and waits up to eight seconds each. Anything that refuses, usually because it is asking you to save, is reported, never forced.
- **Every app row has a submenu** to move it between Close, Keep and Unsorted, or to quit just that one. Choices are saved to the rules file.
- **Helpers roll up.** Chrome's forty helper processes count as Chrome. The numbers match what you feel, not what `ps` prints.
- **Also Turn On Insomnia** switches Insomnia on when you MinMacs, if it is installed, so the freed machine also stays awake for the job.

### Rules file

`~/Library/Application Support/MinMacs/rules.json`, written with sensible defaults on first run and editable by hand (*Edit Rules…* opens it). Two arrays of bundle ids; a trailing `*` matches a prefix.

```json
{ "keep":  ["com.apple.Terminal", "com.microsoft.VSCode", "com.jetbrains.*", "no.guerrilla.insomnia", "…"],
  "close": ["com.google.Chrome", "com.spotify.client", "us.zoom.xos", "com.adobe.*", "…"] }
```

Defaults keep terminals, editors and IDEs, AI apps, containers and databases, password managers and a few utilities. Defaults close browsers, media, communication, creative suites, office apps, games and stores. Everything else is unsorted.

## CLI and agents

The same binary is a command line tool. Nothing here needs the menu bar app to be running.

```sh
minmacs plan               # what MinMacs would close, kept essentials, unsorted apps, reclaimable totals
minmacs plan --json        # the same as JSON, for agents
minmacs run                # close the close-list apps, asks y/N first
minmacs run --yes          # no prompt
minmacs run --yes --only com.google.Chrome
minmacs restore            # relaunch what the last run closed, in the background
minmacs rules              # print the rules file path
```

Exit codes: 0 done, 1 aborted, 2 usage, 3 some apps refused to quit (they are probably asking to save).

The menu bar app also answers a URL scheme: `open minmacs://run` (with confirmation), `minmacs://run-now` (without), `minmacs://restore`, `minmacs://login-on`, `minmacs://login-off`, `minmacs://quit`.

**For an agent** preparing a Mac for a long job:

```sh
minmacs plan --json | jq '.close[] | .name'      # tell the user what will go
minmacs run --yes                                # then do it
open insomnia://on                               # keep the Mac awake for the run
```

## How it works

Every four seconds MinMacs samples all processes through `libproc`, computes CPU as the change in CPU time over wall time, reads physical memory footprint, and attributes each process to the app macOS holds responsible for it, the same grouping Activity Monitor uses, with a parent-chain fallback. The app itself idles at 0% CPU and about 15 MB. Three Objective-C files, no dependencies, builds with clang alone.

## Build from a checkout

```sh
git clone https://github.com/FRIKKern/minmacs.git && cd minmacs
./build.sh                 # universal build, installs app and CLI link
./build.sh --no-install
```

See [CHANGELOG.md](CHANGELOG.md) and, for AI agents working on the code, [AGENTS.md](AGENTS.md).

## Limits

- Quitting a browser drops what its tabs were doing. Tabs come back on relaunch; a half-written form does not.
- macOS system processes are shown for information but never touched. If Spotlight or Photos analysis is eating CPU, MinMacs tells you, it cannot stop them.
- Not notarised. Building locally sidesteps Gatekeeper; the release zip needs a right-click → Open once.

## License

MIT. Made by [Frikk Jarl](https://github.com/FRIKKern).
