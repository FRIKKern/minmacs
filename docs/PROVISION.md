# Provisioning a Mac

`tools/provision.sh` brings a Mac to the state a fleet Mac driven by BarkBot needs, decisions D3 and D9, and says exactly what still needs a person, with the one-time command for each. It is safe to run again: a second run finds everything in place and does nothing.

```sh
tools/provision.sh --fleet --dry-run    # what it would do on a fleet Mac; changes nothing
tools/provision.sh --fleet              # do it
tools/provision.sh --dev                # a person's own Mac: unattended off, the rest left to them
tools/provision.sh --json               # no mode: installs and changes nothing, only reports
curl -fsSL https://raw.githubusercontent.com/FRIKKern/minmacs/main/tools/provision.sh | sh -s -- --fleet
```

## What it does

1. **MinMacs.** When none is installed, or it is older than the newest canary, it installs that canary with `canary.sh update`, which checks the zip's checksum, health-checks the app and rolls back when it does not come up. In a checkout that is `tools/canary.sh`, else the `canary.sh` published with the canary. It never builds. On a fleet Mac another commit of the same version is replaced by the canary; on a person's Mac it stays, with a note.
2. **The mode.** `--fleet` runs `minmacs unattended on`, starts the app when it does not run, and turns on Insomnia's Awake While Agents Work, lid mode when the sudoers rule is in place, and `insomnia screen off`, so the screen stays lit with the lid shut and screen tasks can run lid-closed. It turns Open at Login on through `minmacs://login-on`. `--dev` runs `minmacs unattended off` and changes nothing else.
3. **What still needs a person,** read from `provision` in [`minmacs device --json`](cli/device.md):
   - the sudoers rule for lid mode: `minmacs insomnia lid on`, which shows macOS's administrator dialog once. While unattended that turn is refused, so on a fleet Mac the command is `minmacs unattended off && minmacs insomnia lid on && minmacs unattended on`;
   - notifications, in System Settings > Notifications;
   - the login item, when macOS waits for its approval in System Settings > General > Login Items;
   - Gatekeeper, when the app carries a quarantine flag, as an app from a browser download does: `xattr -dr com.apple.quarantine <app>`;
   - FileVault, as a note: after a restart the Mac waits at the login window, offline, until a person types the password. Nothing lets a Mac unlock itself unattended. Before each planned restart a person runs `sudo fdesetup authrestart`, which takes the password once and unlocks the disk at the next start only.
4. **Machine checks it only reports:** the firewall, automatic macOS updates (a fleet risk: a restart nobody planned, then the FileVault login window), display sleep, free disk on the home volume, and the computer name. Each note prints the command a person would run.

It never runs `sudo` and never asks for a password. It changes nothing but MinMacs's own app and prefs, through MinMacs's own verbs and `canary.sh`.

## The JSON

`--json` prints one object on stdout, and progress on stderr:

| Field | What it holds |
|---|---|
| `schema`, `mode`, `dryRun` | 1; `fleet`, `dev` or `check`; whether it was a dry run |
| `installed`, `version`, `canary` | MinMacs answers `version`; its `CFBundleVersion`; the newest canary's stamp, null when it could not be read |
| `unattended` | the pref `core.unattended` after the run, or after the run a dry run describes |
| `actions` | what it did, or with `--dry-run` what it would do, each starting with `would` |
| `done` | what is in place |
| `needsPerson` | `{what, command}` for each thing only a person can do, once |
| `warnings` | notes, each with the command a person would run |
| `checks` | `firewall`, `automaticMacOSUpdates` and `fileVault` as `on`, `off`, `unset` or `unknown`; `displaySleepMinutes`, `diskFreeBytes`, `diskTotalBytes` and `computerName` |

`./test.sh provision` runs it with `--dry-run` against fixture Macs: a fake `minmacs`, firewall, FileVault and `sudo`, and a fake canary release, so nothing reaches the network or changes this Mac.
