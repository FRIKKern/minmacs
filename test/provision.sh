# ===== provision: what a fleet Mac needs, and what still needs a person, D3 and D9 =====
# Sourced by test.sh after core. tools/provision.sh runs here only with --dry-run, against fixture Macs inside
# $MINMACS_HOME: a fake minmacs in test/provision that answers from a fixture device --json and writes each call it
# gets, fake fdesetup and socketfilterfw, a fake sudo that only writes that it was called, a SoftwareUpdate prefs file
# of its own, a fixture app folder and a fake canary release folder, so nothing reaches the network. One case runs the
# built binary, cold, in a home of its own. Nothing here changes this Mac or its prefs.
pv="$(cd "$MINMACS_HOME" && pwd -P)/provision.$$"
mkdir -p "$pv"
PV_TOOLS="$ROOT/test/provision"
pv_limit() { perl -e 'alarm shift; exec @ARGV' "$@"; }

# pv_mac <name> <key=value...>: a fixture Mac. The words go to device.py, and a few are the Mac's other facts:
# pref (the unattended pref), firewall (1 or 0), filevault (On or Off), auto (the automatic update pref), inApp.
pv_mac() {
  n="$1"; shift
  d="$pv/$n"; rm -rf "$d"; mkdir -p "$d/app/MinMacs.app" "$d/swu"
  python3 -I "$PV_TOOLS/device.py" "$d/device.json" "$@"
  pref=false; fw=1; fv=Off; auto=false; inapp=1
  for w in "$@"; do
    case "$w" in pref=*) pref=${w#pref=} ;; firewall=*) fw=${w#firewall=} ;; filevault=*) fv=${w#filevault=} ;;
                 auto=*) auto=${w#auto=} ;; inApp=false) inapp=0 ;; esac
  done
  printf '{"unattended": %s, "pref": %s, "env": null}\n' "$pref" "$pref" >"$d/unattended.json"
  echo "$fw" >"$d/firewall"; echo "$fv" >"$d/filevault"; echo "$inapp" >"$d/in-app"
  [ "$auto" = unset ] || defaults write "$d/swu/su" AutomaticallyInstallMacOSUpdates -bool "$auto"
  mkdir -p "$pv/canary"; printf '{"stamp": "2.0.0+abc1234", "commit": "abc1234"}\n' >"$pv/canary/build.json"
}
# pv_run <name> <out> <provision words...>: runs the checkout's tools/provision.sh on that Mac. PV_BIN, PV_SOURCE and
# PV_SCRIPT name another minmacs, canary source or script for one run.
pv_run() {
  n="$1"; o="$2"; shift 2; d="$pv/$n"
  pv_limit 60 env PATH="$PV_TOOLS:$PATH" PV_MAC="$d" MINMACS_BIN="${PV_BIN:-$PV_TOOLS/minmacs}" MINMACS_APP="$d/app/MinMacs.app" \
    MINMACS_CANARY_SOURCE="${PV_SOURCE:-$pv/canary}" MINMACS_PROVISION_FIREWALL="$PV_TOOLS/socketfilterfw" \
    MINMACS_PROVISION_SWU="$d/swu/su" MINMACS_CANARY_REPO=none/none sh "${PV_SCRIPT:-$ROOT/tools/provision.sh}" "$@" \
    </dev/null >"$d/$o" 2>"$d/$o.err"
}
pv_j() { json "$2" <"$pv/$1"; }
# The verbs the fake minmacs got that change something: anything but version, device --json, unattended --json.
pv_changes() { grep -vE '^(version|device --json|unattended --json)$' "$pv/$1/calls.log" 2>/dev/null | paste -sd'|' -; }

echo "-- the script: POSIX sh, and it never runs sudo"
check "provision: sh -n passes" 0 "$(sh -n tools/provision.sh; echo $?)"
check "provision: bash --posix -n passes" 0 "$(bash --posix -n tools/provision.sh; echo $?)"
# A sudo appears only inside a string a person reads, never as a command: not at a line's start, after ; & | ( or
# a keyword, in $( or after exec, env, nice or command.
pv_sudo='(^|[;&|(]|\$\(|\b(then|do|else|exec|env|command)|nice( -n [0-9]+)?)[[:space:]]*sudo\b'
check "provision: no line runs sudo" "" "$(grep -nE "$pv_sudo" tools/provision.sh | paste -sd' ' -)"
printf '  sudo a\nx=$(sudo b)\nif c; then sudo d; fi\nnice -n 10 sudo e\nwarn "a person runs: sudo f"\n' >"$pv/planted.sh"
check "provision: and that check finds a planted sudo, not a printed one" "1 2 3 4" "$(grep -nE "$pv_sudo" "$pv/planted.sh" | cut -d: -f1 | paste -sd' ' -)"
check "provision: it never builds" "" "$(grep -nE '(^|[;&|(]|then|do)[[:space:]]*(sh |\./)?(build\.sh|install\.sh)' tools/provision.sh | paste -sd' ' -)"
check "provision: it writes no prefs with defaults" "" "$(grep -nE 'defaults (write|delete)|PlistBuddy' tools/provision.sh | grep -v 'sudo defaults write' | paste -sd' ' -)"

echo "-- a fresh fleet Mac, --fleet --dry-run"
pv_mac fresh displaySleep=10 name="Ada’s MacBook Pro" build=2.0.0+0ld0000 firewall=0 filevault=On auto=true
pv_run fresh out.json --fleet --dry-run --json
check "provision: exits 0" 0 "$?"
check "provision: --json is one object of the documented shape" \
  "schema mode dryRun installed version canary unattended actions done needsPerson warnings checks" \
  "$(pv_j fresh/out.json "' '.join(j.keys())")"
check "provision: needsPerson entries are {what, command}" ok \
  "$(pv_j fresh/out.json "'ok' if j['needsPerson'] and all(sorted(x) == ['command', 'what'] for x in j['needsPerson']) else j['needsPerson']")"
check "provision: the checks have their keys" "automaticMacOSUpdates computerName diskFreeBytes diskTotalBytes displaySleepMinutes fileVault firewall" \
  "$(pv_j fresh/out.json "' '.join(sorted(j['checks']))")"
check "provision: mode, dry run, installed, the versions" "fleet True True 2.0.0+0ld0000 2.0.0+abc1234" \
  "$(pv_j fresh/out.json "' '.join(str(x) for x in (j['mode'], j['dryRun'], j['installed'], j['version'], j['canary']))")"
check "provision: it would install the canary through canary.sh update" 1 \
  "$(pv_j fresh/out.json "sum('install MinMacs 2.0.0+abc1234' in a and 'canary.sh runs update' in a for a in j['actions'])")"
check "provision: it would turn unattended on and keep the screen lit" "1 1" \
  "$(pv_j fresh/out.json "' '.join(str(sum(w in a for a in j['actions'])) for w in ('(minmacs unattended on)', '(minmacs insomnia screen off)'))")"
check "provision: every action says would" ok "$(pv_j fresh/out.json "'ok' if all(a.startswith('would ') for a in j['actions']) else j['actions']")"
check "provision: no lid mode without the rule, which needs a person" "0 1" \
  "$(pv_j fresh/out.json "'%d %d' % (sum('insomnia lid on)' in a for a in j['actions']), sum(x['command'] == 'minmacs unattended off && minmacs insomnia lid on && minmacs unattended on' for x in j['needsPerson']))")"
check "provision: it reports as unattended, as the run would leave it" True "$(pv_j fresh/out.json "j['unattended']")"
check "provision: the fleet notes: firewall, updates, display sleep, name, FileVault" "1 1 1 1 1" \
  "$(pv_j fresh/out.json "' '.join(str(sum(w in x for x in j['warnings'])) for w in ('firewall is off', 'automatic macOS updates are on', 'display sleeps after 10 min', 'computer name', 'fdesetup authrestart'))")"
check "provision: each admin step is printed with sudo for a person" 5 "$(pv_j fresh/out.json "sum('sudo ' in x for x in j['warnings'])")"
check "provision: the checks hold the fixture's facts" "off on on 10 Ada’s MacBook Pro" \
  "$(pv_j fresh/out.json "' '.join(str(j['checks'][k]) for k in ('firewall', 'automaticMacOSUpdates', 'fileVault', 'displaySleepMinutes', 'computerName'))")"
check "provision: --dry-run ran no verb that changes something" "" "$(pv_changes fresh)"
check "provision: sudo was never called" no "$([ -e "$pv/fresh/sudo.log" ] && echo yes || echo no)"
check "provision: --json keeps stdout to the object, progress on stderr" "0 3" \
  "$(grep -c '^==>' "$pv/fresh/out.json") $(grep -c '^==> Would' "$pv/fresh/out.json.err")"

pv_run fresh out.txt --fleet --dry-run
check "provision: the text says dry run, and names what needs a person" "1 1 1" \
  "$(grep -c 'dry run: nothing was changed' "$pv/fresh/out.txt") $(grep -c '^Needs a person, once:' "$pv/fresh/out.txt") $(grep -c '^      minmacs unattended off && minmacs insomnia lid on && minmacs unattended on$' "$pv/fresh/out.txt")"
check "provision: the text lists the checks" 6 "$(sed -n '/^Checks, reported/,$p' "$pv/fresh/out.txt" | grep -cE '^  (Firewall|Automatic macOS updates|FileVault|Display sleep|Free disk|Computer name) ')"

echo "-- the rule in place: lid mode is turned on"
pv_mac rule lidRule=true pref=true screenOff=false
pv_run rule out.json --fleet --dry-run --json
check "provision: with the rule it would turn lid mode on, and nothing else" "would turn Insomnia's lid mode on (minmacs insomnia lid on)" "$(pv_j rule/out.json "'|'.join(j['actions'])")"
check "provision: and the rule needs no person" "[]" "$(pv_j rule/out.json "j['needsPerson']")"

echo "-- a fleet Mac with everything in place: nothing to do, twice"
pv_mac ready lidRule=true lidMode=true pref=true unattended=true screenOff=false
pv_run ready a.json --fleet --dry-run --json; pv_run ready b.json --fleet --dry-run --json
check "provision: no action, no person, no note" "[] [] []" "$(pv_j ready/a.json "'%s %s %s' % (j['actions'], j['needsPerson'], j['warnings'])")"
check "provision: done names each part" 9 "$(pv_j ready/a.json "len(j['done'])")"
check "provision: a second run says the same" same "$(cmp -s "$pv/ready/a.json" "$pv/ready/b.json" && echo same || echo differs)"
pv_run ready a.txt --fleet --dry-run
check "provision: the text says nothing needs a person" 1 "$(grep -c '^Needs a person: nothing.$' "$pv/ready/a.txt")"

echo "-- what a person must allow: notifications, the login item, Gatekeeper"
pv_mac allow lidRule=true lidMode=true pref=true screenOff=false notifications=false login=requiresApproval
xattr -w com.apple.quarantine "0081;00000000;Safari;" "$pv/allow/app/MinMacs.app"
pv_run allow out.json --fleet --dry-run --json
check "provision: notifications, the login item and the quarantine flag need a person" \
  "open 'x-apple.systempreferences:com.apple.Notifications-Settings.extension'|open 'x-apple.systempreferences:com.apple.LoginItems-Settings.extension'|xattr -dr com.apple.quarantine '$pv/allow/app/MinMacs.app'" \
  "$(pv_j allow/out.json "'|'.join(x['command'] for x in j['needsPerson'])")"
check "provision: the login item is named by its place in System Settings" 1 "$(pv_j allow/out.json "sum('System Settings > General > Login Items' in x['what'] for x in j['needsPerson'])")"

echo "-- the app does not run, and the login item is not registered"
pv_mac cold inApp=false login=notRegistered notifications=null
pv_run cold out.json --fleet --dry-run --json
check "provision: it would start the app, then turn the login item on" "1 1" \
  "$(pv_j cold/out.json "'%d %d' % (sum(a.startswith('would start MinMacs') for a in j['actions']), sum('minmacs://login-on' in a for a in j['actions']))")"
check "provision: the notification permission is a note when no app answers" 1 "$(pv_j cold/out.json "sum('notification permission' in x for x in j['warnings'])")"
check "provision: still no verb that changes something" "" "$(pv_changes cold)"

echo "-- a person's own Mac, --dev"
pv_mac dev pref=true unattended=true displaySleep=10 name="Ada’s MacBook Pro" build=2.0.0+0ld0000 filevault=On auto=true firewall=0
pv_run dev out.json --dev --dry-run --json
check "provision: dev would turn unattended off, and only that" "would turn unattended off, as a person uses this Mac (minmacs unattended off)" "$(pv_j dev/out.json "'|'.join(j['actions'])")"
check "provision: dev leaves another commit of the same version as it is, and says so" 1 "$(pv_j dev/out.json "sum('not the newest canary' in x for x in j['warnings'])")"
check "provision: dev reports unattended off" False "$(pv_j dev/out.json "j['unattended']")"
check "provision: dev needs no person for lid mode it does not use" "[]" "$(pv_j dev/out.json "j['needsPerson']")"
check "provision: dev has no fleet notes: updates, display sleep, name, FileVault" "0 0 0 0" \
  "$(pv_j dev/out.json "' '.join(str(sum(w in x for x in j['warnings'])) for w in ('automatic macOS updates', 'display sleeps', 'computer name', 'FileVault'))")"
check "provision: dev still reports the firewall, and the checks" "1 on" "$(pv_j dev/out.json "'%d %s' % (sum('firewall is off' in x for x in j['warnings']), j['checks']['fileVault'])")"
pv_mac dev2 pref=false build=1.9.0+aaa version=1.9.0
pv_run dev2 out.json --dev --dry-run --json
check "provision: dev installs a canary of a newer version, and nothing else" "1 1" \
  "$(pv_j dev2/out.json "'%d %d' % (len(j['actions']), sum('install MinMacs 2.0.0+abc1234' in a for a in j['actions']))")"
pv_mac newer build=2.1.0+fff version=2.1.0
pv_run newer out.json --fleet --dry-run --json
check "provision: a build newer than the canary stays, with a note" "0 1" \
  "$(pv_j newer/out.json "'%d %d' % (sum('install' in a for a in j['actions']), sum('newer than the newest canary' in x for x in j['warnings']))")"

echo "-- no MinMacs, and no mode"
pv_mac none
PV_BIN="$pv/none/no-minmacs" pv_run none out.json --fleet --dry-run --json
unset PV_BIN PV_SOURCE PV_SCRIPT   # a prefix on a function call outlives the call in sh
check "provision: none installed: it would install the canary, and do nothing else yet" "False 1" \
  "$(pv_j none/out.json "'%s %d' % (j['installed'], len(j['actions']))")"
PV_BIN="$pv/none/no-minmacs" PV_SOURCE="$pv/none/no-release" pv_run none dark.json --fleet --dry-run --json
unset PV_BIN PV_SOURCE PV_SCRIPT   # a prefix on a function call outlives the call in sh
check "provision: no MinMacs and no canary to read: a person installs it, with the command" "0 curl -fsSL https://github.com/none/none/releases/download/canary/canary.sh | sh -s update" \
  "$(pv_j none/dark.json "'%d %s' % (len(j['actions']), j['needsPerson'][0]['command'])")"
pv_mac check build=1.9.0+aaa version=1.9.0
pv_run check out.json --json
check "provision: with no mode it changes nothing and installs nothing" "check []" "$(pv_j check/out.json "'%s %s' % (j['mode'], j['actions'])")"
# Outside a checkout, as when piped from the release, the canary.sh published with the canary does the update.
cp tools/provision.sh "$pv/provision.sh"
PV_SCRIPT="$pv/provision.sh" pv_run dev2 out2.json --dev --dry-run --json
unset PV_BIN PV_SOURCE PV_SCRIPT   # a prefix on a function call outlives the call in sh
check "provision: outside a checkout it uses the published canary.sh, and downloads nothing in a dry run" "1 no" \
  "$(pv_j dev2/out2.json "sum('the canary.sh published with it' in a for a in j['actions'])") $(ls "$pv/canary/canary.sh" >/dev/null 2>&1 && echo yes || echo no)"
check "provision: an unknown option is a usage error" 2 "$(sh tools/provision.sh --nope >/dev/null 2>&1; echo $?)"

echo "-- the built binary, cold, in a home of its own"
pv_mac real
mkdir -p "$pv/real/home" "$pv/real/bin"
printf '#!/bin/sh\nMINMACS_HOME="%s" MINMACS_COLD=1 exec "%s" "$@"\n' "$pv/real/home" "$BIN" >"$pv/real/bin/minmacs"; chmod +x "$pv/real/bin/minmacs"
PV_BIN="$pv/real/bin/minmacs" pv_run real fleet.json --fleet --dry-run --json
unset PV_BIN PV_SOURCE PV_SCRIPT   # a prefix on a function call outlives the call in sh
check "provision: with the built binary it reads device --json" "True $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)" \
  "$(pv_j real/fleet.json "'%s %s' % (j['installed'], j['version'])")"
check "provision: a fresh home would get unattended on, and the app started" "1 1" \
  "$(pv_j real/fleet.json "'%d %d' % (sum('(minmacs unattended on)' in a for a in j['actions']), sum(a.startswith('would start MinMacs') for a in j['actions']))")"
check "provision: the real disk and display-sleep facts arrive" ok \
  "$(pv_j real/fleet.json "'ok' if isinstance(j['checks']['diskFreeBytes'], int) and isinstance(j['checks']['displaySleepMinutes'], int) else j['checks']")"
check "provision: the dry run left the home's unattended pref off" false \
  "$("$pv/real/bin/minmacs" unattended --json </dev/null 2>/dev/null | json "str(j['pref']).lower()")"
PV_BIN="$pv/real/bin/minmacs" pv_run real dev.json --dev --dry-run --json
unset PV_BIN PV_SOURCE PV_SCRIPT   # a prefix on a function call outlives the call in sh
check "provision: dev on the built binary has nothing to turn off" "[]" "$(pv_j real/dev.json "[a for a in j['actions'] if 'unattended' in a]")"
check "provision: sudo was never called by the script, in any case" "" "$(ls "$pv"/*/sudo.log 2>/dev/null | paste -sd' ' -)"
