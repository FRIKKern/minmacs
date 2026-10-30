# CLI

This page is generated from `minmacs help --json` by `test/docs/clidoc.py`. `./test.sh docs` fails when it does not match the built binary. To write it again after a verb changes:

```sh
python3 -I test/docs/clidoc.py build/MinMacs.app/Contents/MacOS/MinMacs > docs/CLI.md
```

The app binary is also the command line tool. `install.sh` and `build.sh --install` link it as `~/.local/bin/minmacs`. When the app runs, the CLI hands each verb to it over `core.sock` in the support folder. When no app answers, it builds a snapshot itself and answers from that.

## Exit codes

- **0.** OK.
- **1.** The verb ran and something did not work, or nothing matched.
- **2.** An unknown verb, a missing argument or a bad value.
- **3.** The verb changes things, and no MinMacs app answers on core.sock.

## minmacs

### MinMacs

#### `apps`

```
apps [list | quit <bundle-id|pid> [--force] | trim [<bundle-id>] | keep|close|unsorted <bundle-id> | serving on|off <bundle-id> | classify <url>] [--json] [--dry-run]
```

Flags: `--force`, `--json`, `--dry-run`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `status`

What each expert sees, as its menu header says it.

```
status [--json]
```

Flags: `--json`.

#### `work`

Each workstream, or Wrap Up of a finished one.

```
work [path] [--here] [--json] | work wrap-up <id> [--dry-run] [--json]
```

Flags: `--here`, `--json`, `--dry-run`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `review`

The last review, or a new one with --now.

```
review [expert] [--now] [--json]
```

Flags: `--now`, `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `investigate`

Look deeper into one, after you confirm its cost.

```
investigate <finding|workstream|path> [question] [--yes] [--json]
```

Flags: `--yes`, `--json`.

#### `tidy`

What each mode would act on, and act on it.

```
tidy [expert] [--dry-run] [--mode <mode>] [--json]
```

Flags: `--dry-run`, `--mode`, `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `where`

The terminal tab, pane or app it runs in.

```
where <pid> | where --port <port> [--go] [--json]
```

Flags: `--port`, `--go`, `--json`.

#### `restore`

Undo the last run, or one record.

```
restore [rid] [--list] [--expert <expert>] [--limit <n>] [--dry-run] [--json]
```

Flags: `--list`, `--expert`, `--limit`, `--dry-run`, `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `mode`

Show or set an expert's mode.

```
mode <expert> [idle|proactive|eager] [--json]
```

Flags: `--json`.

#### `version`

The version.

```
version [--json]
```

Flags: `--json`.

#### `help`

Every verb.

```
help [--json]
```

Flags: `--json`.

### LocoHost

#### `hosts`

Every localhost, or what one port is, how it runs and why.

```
hosts [port] [--json]
```

Flags: `--json`.

### WorkForest

#### `trees`

Every git worktree, whether it is merged, and what removing it frees.

```
trees [list|explain <path>|review|plan|auto|clean-up|remove <path>|restore <id|path>|removed|keep <path>|protect <path>|prune <path>|rules] [--all] [--mode <mode>] [--model <model>] [--path <path>] [--days <n>] [--off] [--fresh] [--review] [--yes] [--dry-run] [--json]
```

Flags: `--all`, `--mode`, `--model`, `--path`, `--days`, `--off`, `--fresh`, `--review`, `--yes`, `--dry-run`, `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `worktrees`

Every git worktree, whether it is merged, and what removing it frees.

```
worktrees [list|explain <path>|review|plan|auto|clean-up|remove <path>|restore <id|path>|removed|keep <path>|protect <path>|prune <path>|rules] [--all] [--mode <mode>] [--model <model>] [--path <path>] [--days <n>] [--off] [--fresh] [--review] [--yes] [--dry-run] [--json]
```

Flags: `--all`, `--mode`, `--model`, `--path`, `--days`, `--off`, `--fresh`, `--review`, `--yes`, `--dry-run`, `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

### Noo-Noo

#### `clutter`

```
clutter [list | show <id|path> | trends | check <path> | scan] [--json] [--dry-run]
```

Flags: `--json`, `--dry-run`.

#### `clean`

Moves clutter to the Trash with undo, or with --command runs the row's own cleanup, which cannot be undone.

```
clean <id|path|row> ... [--command] | --finished | --leftovers | --undo [rid] [--json] [--dry-run]
```

Flags: `--command`, `--finished`, `--leftovers`, `--undo`, `--json`, `--dry-run`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

### Insomnia

#### `awake`

```
awake [--json]
```

Flags: `--json`.

## The old names

The binary looks at the name it was started under. A link named `locohost`, `workforest`, `noo-noo` or `insomnia` answers that expert's verbs first, then the verbs of `minmacs`. Below is what differs from `minmacs` under each name.

### locohost

#### `where`

The cmux tab, tmux pane, terminal tab or app a server runs in.

```
where <port> [--go] [--json]
```

Flags: `--go`, `--json`.

#### `review`

Ask the model which localhosts are in use.

```
review [--mode name] [--model name] [--port p] [--json]
```

Flags: `--mode`, `--model`, `--port`, `--json`.

#### `restore`

List the servers LocoHost stopped, or start one again.

```
restore [record id|port] [--json]
```

Flags: `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `list`

Every localhost, its cost, state and who started it.

```
locohost list [--all] [--json]
```

Flags: `--all`, `--json`.

#### `who`

The process on a port, its folder, branch, command and clients.

```
locohost who <port> [--json]
```

Flags: `--json`.

#### `explain`

What it is, how it runs, why it is there and what it wastes.

```
locohost explain <port> [--json]
```

Flags: `--json`.

#### `ready`

Wait until the port answers; exit 0 ready, 1 timed out.

```
locohost ready <port> [--http] [--timeout s]
```

Flags: `--http`, `--timeout`.

#### `free`

The first free port at or above port, 3000 by default.

```
locohost free [port]
```

#### `waste`

What each dev server burned since it was last used.

```
locohost waste [--json]
```

Flags: `--json`.

#### `summary`

The review's words and what the mode would do.

```
locohost summary [--mode name] [--json]
```

Flags: `--mode`, `--json`.

#### `auto`

One round of the mode.

```
locohost auto [--mode name] [--port p] [--dry-run] [--review] [--force] [--json]
```

Flags: `--mode`, `--port`, `--dry-run`, `--review`, `--force`, `--json`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `mode`

Show or set the mode.

```
locohost mode [idle|proactive|eager]
```

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `idle`

What Close Idle would stop right now.

```
locohost idle [--port p] [--json]
```

Flags: `--port`, `--json`.

#### `close-idle`

Stop every confirmed idle server.

```
locohost close-idle [--yes] [--force] [--port p] [--review]
```

Flags: `--yes`, `--force`, `--port`, `--review`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `close`

Stop one server, SIGTERM, then SIGKILL on a second request.

```
locohost close <port|pid> [--yes] [--force]
```

Flags: `--yes`, `--force`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `open`

Open it in the browser.

```
locohost open <port>
```

#### `stopped`

What LocoHost stopped, with the command to start each again.

```
locohost stopped [--json]
```

Flags: `--json`.

#### `restart`

Start the server LocoHost last stopped on that port again.

```
locohost restart <port>
```

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `keep`

No mode stops it for this many hours, 4 by default, 0 clears.

```
locohost keep <port> [hours]
```

It changes things, so it runs only through the running app, unless `--dry-run` is given.

#### `rules`

Print the rules file path.

```
locohost rules
```

### workforest

Every verb is the same as under `minmacs`.

### noo-noo

Every verb is the same as under `minmacs`.

### insomnia

#### `insomnia`

```
insomnia on|off|toggle | agents on|off | lid on|off | screen on|off | heat on|off | set battery|unplugged|offline|quiet <minutes or percent|never> | hold <pid> [reason] [--json] [--dry-run]
```

Flags: `--json`, `--dry-run`.

It changes things, so it runs only through the running app, unless `--dry-run` is given.

### Commands of the 1.x apps

An old command that is no verb under that name is rewritten to 2.0 words before it runs. Under an old name, the expert's own verb wins over the rewrite. Under `minmacs`, any 2.0 verb wins. `<arg>` is the old command's first argument. The rewrites are read from `MMLegacyWords` in `Sources/CLI/MMCLI.m`, and only the ones that apply are listed.

Under `minmacs`:

- `minmacs plan` becomes `minmacs tidy minmacs --dry-run`.
- `minmacs run` becomes `minmacs tidy minmacs`.
- `minmacs agents` becomes `minmacs work`.

Under `locohost`:

None apply. Every old command is a verb of its own under this name.

Under `workforest`:

- `workforest list` becomes `workforest trees list`.
- `workforest explain` becomes `workforest trees explain <arg>`.
- `workforest review` becomes `workforest trees review`.
- `workforest summary` becomes `workforest trees plan`.
- `workforest auto` becomes `workforest trees auto`.
- `workforest clean-up` becomes `workforest trees clean-up`.
- `workforest remove` becomes `workforest trees remove <arg>`.
- `workforest restore` becomes `workforest trees restore <arg>`.
- `workforest removed` becomes `workforest trees removed`.
- `workforest keep` becomes `workforest trees keep <arg>`.
- `workforest prune` becomes `workforest trees prune <arg>`.
- `workforest fetch` becomes `workforest trees fetch`.
- `workforest rules` becomes `workforest trees rules`.
- `workforest mode` becomes `workforest mode workforest <arg>`.
