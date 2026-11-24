#!/bin/sh
# Brings a Mac to the state a BarkBot-driven fleet Mac needs, or checks a person's own development Mac, and says
# exactly what still needs a person, with the one-time command for each. Decisions D3 and D9. Safe to run again.
#
#   tools/provision.sh --fleet [--dry-run] [--json]   a Mac that runs with nobody at it
#   tools/provision.sh --dev [--dry-run] [--json]     a person's own Mac: unattended off, the rest left to them
#   tools/provision.sh [--json]                       no mode: installs and changes nothing, only reports
#   curl -fsSL https://raw.githubusercontent.com/FRIKKern/minmacs/main/tools/provision.sh | sh -s -- --fleet
#
# What it does, in order:
#   1. MinMacs: none installed, or older than the newest canary, installs that canary with canary.sh update, which
#      checks its checksum, health-checks the app and rolls back. In a checkout it runs tools/canary.sh, else the
#      canary.sh published with the canary. It never builds.
#   2. --fleet: minmacs unattended on; the app started when it does not run; Insomnia's agents on, lid mode on when the
#      sudoers rule is in place, the screen kept lit with the lid shut (insomnia screen off); the login item on.
#      --dev: minmacs unattended off, and nothing else.
#   3. A report from minmacs device --json: what is done, and what still needs a person, with its exact command.
#   4. Machine checks it only reports: the firewall, automatic macOS updates, display sleep, free disk, the name.
# --dry-run says what it would do and changes nothing. --json prints one object for BarkBot or Supervision:
#   {schema, mode, dryRun, installed, version, canary, unattended, actions[], done[], needsPerson[{what, command}],
#    warnings[], checks{}}
#
# It never runs sudo and never asks for a password: what needs an administrator is printed for a person to run. It
# changes nothing but MinMacs's own app and prefs, through MinMacs's own verbs and canary.sh.
#
# Environment, also for the checks in test/provision.sh:
#   MINMACS_BIN             the minmacs to use. Default: minmacs on PATH, else ~/.local/bin/minmacs
#   MINMACS_APP             the app it belongs to. Default: the app the link reaches, else ~/Applications/MinMacs.app
#   MINMACS_CANARY_REPO     owner/name of the repo whose "canary" prerelease is read. Default FRIKKern/minmacs
#   MINMACS_CANARY_SOURCE   a folder or URL that holds the canary's build.json and canary.sh, in place of the release
#   MINMACS_PROVISION_FIREWALL  the socketfilterfw to ask. MINMACS_PROVISION_SWU  the SoftwareUpdate prefs to read.
set -eu

MODE=check; DRY=0; JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fleet) MODE=fleet; shift ;;
    --dev) MODE=dev; shift ;;
    --dry-run) DRY=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,31p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'provision: unknown option %s. Try --help.\n' "$1" >&2; exit 2 ;;
  esac
done
[ "$(uname -s)" = Darwin ] || { echo "provision: MinMacs is a macOS app." >&2; exit 1; }

REPO="${MINMACS_CANARY_REPO:-FRIKKern/minmacs}"
RELEASE="https://github.com/$REPO/releases/download/canary"
FIREWALL="${MINMACS_PROVISION_FIREWALL:-/usr/libexec/ApplicationFirewall/socketfilterfw}"
SWU="${MINMACS_PROVISION_SWU:-/Library/Preferences/com.apple.SoftwareUpdate}"
UPDATE_CMD="curl -fsSL $RELEASE/canary.sh | sh -s update"
TAB=$(printf '\t')
TMP=$(mktemp -d "${TMPDIR:-/tmp}/minmacs-provision.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

# Progress goes to stderr under --json, so stdout holds only the object.
say() { if [ "$JSON" = 1 ]; then printf '==> %s\n' "$*" >&2; else printf '==> %s\n' "$*"; fi; }
ACTIONS=""; DONE=""; NEEDS=""; WARN=""
add() { eval "$1=\"\${$1}\$2
\""; }                                      # add LIST line: appends one line to that list
action() { if [ "$DRY" = 1 ]; then add ACTIONS "would $1"; say "Would $1"; else add ACTIONS "$1"; say "$(printf '%s' "$1" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }')"; fi; }
done_() { add DONE "$1"; }
need() { add NEEDS "$1$TAB$2"; }
warn() { add WARN "$1"; }

# One JSON read: prints "path<TAB>value" for each path asked, null for a missing one, an array joined by commas.
jread() {   # file path...
  osascript -l JavaScript - "$@" 2>/dev/null <<'EOF' || true
function run(argv) {
  var t = $.NSString.stringWithContentsOfFileEncodingError(argv[0], 4, null), j;
  if (!t || t.isNil()) return "";
  try { j = JSON.parse(t.js); } catch (e) { return ""; }
  var out = [];
  for (var i = 1; i < argv.length; i++) {
    var v = j;
    argv[i].split(".").forEach(function (k) { v = (v === undefined || v === null) ? undefined : v[k]; });
    out.push(argv[i] + "\t" + (v === undefined || v === null ? "null" : Array.isArray(v) ? v.join(",") : String(v)));
  }
  return out.join("\n");
}
EOF
}
F=""
fact() { printf '%s\n' "$F" | awk -F"$TAB" -v k="$1" '$1 == k { print substr($0, length(k) + 2); exit }'; }

# ---- 1. MinMacs, through the canary ----
find_bin() {
  if [ -n "${MINMACS_BIN:-}" ]; then MM="$MINMACS_BIN"
  elif command -v minmacs >/dev/null 2>&1; then MM=$(command -v minmacs)
  else MM="$HOME/.local/bin/minmacs"; fi
  INSTALLED=false
  [ -x "$MM" ] && "$MM" version </dev/null >/dev/null 2>&1 && INSTALLED=true
  if [ -n "${MINMACS_APP:-}" ]; then APP="$MINMACS_APP"
  else
    APP="$HOME/Applications/MinMacs.app"
    t=$(readlink "$MM" 2>/dev/null || true)
    case "$t" in */MinMacs.app/Contents/MacOS/MinMacs) APP="${t%/Contents/MacOS/MinMacs}" ;; esac
  fi
}
read_device() {
  F=""
  [ "$INSTALLED" = true ] || return 0
  "$MM" device --json </dev/null >"$TMP/device.json" 2>/dev/null || { warn "minmacs device --json did not answer, so this MinMacs predates it"; return 0; }
  "$MM" unattended --json </dev/null >"$TMP/unattended.json" 2>/dev/null || true
  F=$(jread "$TMP/device.json" inApp identity.minmacs.version identity.minmacs.build identity.computerName \
        provision.unattended provision.lidRuleInstalled provision.notificationsAuthorized provision.loginItem \
        lid.insomniaLidMode lid.screenOff awake.agentsMode awake.displaySleepMinutes load.diskFreeBytes load.diskTotalBytes)
  F="$F
$(jread "$TMP/unattended.json" pref | sed 's/^pref/unattended.pref/')"
}
canary_get() {   # name dest: one file of the newest canary
  src="${MINMACS_CANARY_SOURCE:-}"
  case "$src" in
    "") if command -v gh >/dev/null 2>&1 && gh release download canary -R "$REPO" -p "$1" -O "$2" --clobber >/dev/null 2>&1; then return 0; fi
        curl -fsSL "$RELEASE/$1" -o "$2" 2>/dev/null ;;
    http://*|https://*) curl -fsSL "${src%/}/$1" -o "$2" 2>/dev/null ;;
    *) [ -f "$src/$1" ] && cp "$src/$1" "$2" ;;
  esac
}
ver_lt() {   # $1 < $2, both x.y.z
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$1" ]
}
running_pid() { ps -axo pid=,ppid=,comm= | awk -v app="$APP/Contents/MacOS/MinMacs" '$2 == 1 && $3 == app { print $1; exit }'; }

find_bin
read_device
HAVE=$(fact identity.minmacs.build); HAVE_V=$(fact identity.minmacs.version)
[ "$INSTALLED" = true ] && [ -z "$HAVE" ] && HAVE=$("$MM" version 2>/dev/null | awk '{print $2}') && HAVE_V="$HAVE"
CANARY=""; CANARY_V=""
if canary_get build.json "$TMP/build.json"; then
  CANARY=$(jread "$TMP/build.json" stamp | cut -f2); [ "$CANARY" = null ] && CANARY=""
  CANARY_V=${CANARY%%+*}
fi

UPDATE=0
if [ "$MODE" = check ]; then :
elif [ -z "$CANARY" ]; then
  if [ "$INSTALLED" = true ]; then warn "the newest canary of $REPO could not be read, so MinMacs ${HAVE:-?} stays as it is"
  else need "MinMacs is not installed, and the newest canary of $REPO could not be read. Install it once the release answers" "$UPDATE_CMD"; fi
elif [ "$INSTALLED" != true ]; then UPDATE=1
elif [ "$HAVE" = "$CANARY" ]; then :
elif ver_lt "${HAVE_V:-0}" "$CANARY_V"; then UPDATE=1
elif ver_lt "$CANARY_V" "${HAVE_V:-0}"; then warn "MinMacs $HAVE is newer than the newest canary, $CANARY, so it stays"
elif [ "$MODE" = fleet ]; then UPDATE=1            # same version, another commit: a fleet Mac runs the canary exactly
else warn "MinMacs $HAVE is not the newest canary, $CANARY. It stays, as this is a person's Mac. To take the canary: tools/canary.sh update"
fi

if [ "$UPDATE" = 1 ]; then
  # canary.sh reads JSON with python3. Without the Command Line Tools that is a stub that opens an install dialog.
  if ! xcode-select -p >/dev/null 2>&1; then
    need "the Command Line Tools, for python3, which canary.sh needs to install MinMacs" "xcode-select --install"
  else
    HERE=""
    case "$0" in */provision.sh) [ -f "$0" ] && HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P || echo "") ;; esac
    if [ -n "$HERE" ] && [ -f "$HERE/canary.sh" ] && [ -f "$HERE/../build.sh" ]; then CS="$HERE/canary.sh"; CS_FROM="this checkout's tools/canary.sh"
    else CS="$TMP/canary.sh"; CS_FROM="the canary.sh published with it"; fi
    action "install MinMacs $CANARY, the newest canary: $CS_FROM runs update, with its checksum, health check and rollback"
    if [ "$DRY" = 0 ]; then
      [ -f "$CS" ] || canary_get canary.sh "$CS" || { echo "provision: could not download canary.sh" >&2; exit 1; }
      if [ "$JSON" = 1 ]; then nice -n 10 sh "$CS" update </dev/null >&2 || warn "canary.sh update failed; MinMacs is as it was"
      else nice -n 10 sh "$CS" update </dev/null || warn "canary.sh update failed; MinMacs is as it was"; fi
      MINMACS_BIN=""; find_bin; read_device
      HAVE=$(fact identity.minmacs.build); HAVE_V=$(fact identity.minmacs.version)
    fi
  fi
fi
if [ "$INSTALLED" = true ] && [ -n "$CANARY" ] && [ "$HAVE" = "$CANARY" ]; then done_ "MinMacs $HAVE, the newest canary, is installed"
elif [ "$INSTALLED" = true ]; then done_ "MinMacs ${HAVE:-?} is installed"
elif [ "$MODE" = check ]; then need "MinMacs is not installed" "$UPDATE_CMD"; fi

# ---- 2. The mode ----
verb() {   # what, then the minmacs words: runs them unless --dry-run, notes a failure
  what="$1"; shift
  action "$what ($(printf 'minmacs %s' "$*"))"
  [ "$DRY" = 1 ] && return 0
  "$MM" "$@" </dev/null >"$TMP/verb.out" 2>&1 || warn "minmacs $* failed: $(tail -1 "$TMP/verb.out")"
}
IN_APP=$(fact inApp); PREF=$(fact unattended.pref)
if [ "$INSTALLED" = true ] && [ "$MODE" = fleet ]; then
  if [ "$PREF" = true ]; then done_ "unattended is on"; else verb "turn unattended on" unattended on; fi
  if [ "$IN_APP" != true ]; then
    action "start MinMacs, which Insomnia's settings and the login item go through (open -g $APP)"
    if [ "$DRY" = 0 ]; then
      open -g "$APP" 2>/dev/null || true
      n=0; while [ $n -lt 30 ]; do [ -n "$(running_pid)" ] && break; sleep 1; n=$((n + 1)); done
      n=0; while [ $n -lt 10 ]; do read_device; [ "$(fact inApp)" = true ] && break; sleep 2; n=$((n + 1)); done
      IN_APP=$(fact inApp)
      [ "$IN_APP" = true ] || warn "MinMacs did not come up, so Insomnia and the login item are left. Run this again once it runs"
    fi
  fi
  if [ "$IN_APP" = true ] || [ "$DRY" = 1 ]; then
    if [ "$(fact awake.agentsMode)" = true ]; then done_ "Insomnia keeps the Mac awake while agents work"
    else verb "keep the Mac awake while agents work" insomnia agents on; fi
    if [ "$(fact lid.insomniaLidMode)" = true ]; then done_ "Insomnia's lid mode is on"
    elif [ "$(fact provision.lidRuleInstalled)" = true ]; then verb "turn Insomnia's lid mode on" insomnia lid on
    fi
    if [ "$(fact lid.screenOff)" = false ]; then done_ "the screen stays lit with the lid shut, so screen tasks can run"
    else verb "keep the screen lit with the lid shut, so screen tasks can run lid-closed" insomnia screen off; fi
    case "$(fact provision.loginItem)" in
      enabled) done_ "MinMacs opens at login" ;;
      notRegistered) action "turn Open at Login on (open -g -a $APP minmacs://login-on)"
                     [ "$DRY" = 1 ] || open -g -a "$APP" "minmacs://login-on" 2>/dev/null || warn "the login item could not be asked for" ;;
    esac
  fi
elif [ "$INSTALLED" = true ] && [ "$MODE" = dev ]; then
  if [ "$PREF" = true ]; then verb "turn unattended off, as a person uses this Mac" unattended off; else done_ "unattended is off"; fi
fi
# What the actions changed shows in the report, so a real run reads the Mac once more.
[ "$DRY" = 0 ] && [ -n "$ACTIONS" ] && [ "$INSTALLED" = true ] && read_device
UNATTENDED=$(fact unattended.pref); [ -n "$UNATTENDED" ] || UNATTENDED=false
[ "$DRY" = 1 ] && [ "$INSTALLED" = true ] && case "$MODE" in fleet) UNATTENDED=true ;; dev) UNATTENDED=false ;; esac

# ---- 3. What still needs a person ----
FLEETISH=0; { [ "$MODE" = fleet ] || { [ "$MODE" = check ] && [ "$UNATTENDED" = true ]; }; } && FLEETISH=1
if [ "$INSTALLED" = true ]; then
  # Lid mode on without the rule is refused at once while unattended, so the person's one turn goes in between.
  LIDCMD="minmacs insomnia lid on"
  [ "$UNATTENDED" = true ] && LIDCMD="minmacs unattended off && minmacs insomnia lid on && minmacs unattended on"
  if [ "$(fact provision.lidRuleInstalled)" = true ]; then done_ "the sudoers rule for lid mode is in place"
  elif [ "$FLEETISH" = 1 ] || [ "$(fact lid.insomniaLidMode)" = true ]; then
    need "the sudoers rule for Insomnia's lid mode, so the Mac runs with the lid shut. macOS shows its administrator dialog once" "$LIDCMD"
  fi
  case "$(fact provision.notificationsAuthorized)" in
    true) done_ "MinMacs may show notifications" ;;
    false) need "notifications: allow MinMacs in System Settings > Notifications, so a notice can reach a person" \
             "open 'x-apple.systempreferences:com.apple.Notifications-Settings.extension'" ;;
    *) [ "$FLEETISH" = 1 ] && warn "the notification permission can be read only by the running app, which did not answer" ;;
  esac
  case "$(fact provision.loginItem)" in
    requiresApproval) need "the login item: approve MinMacs in System Settings > General > Login Items, so it starts after a restart" \
                        "open 'x-apple.systempreferences:com.apple.LoginItems-Settings.extension'" ;;
    notFound) [ "$FLEETISH" = 1 ] && warn "macOS does not find MinMacs's login item: is $APP the app the link reaches?" ;;
    notRegistered) [ "$FLEETISH" = 1 ] && [ "$DRY" = 0 ] && warn "the login item is not registered yet. Run this again once MinMacs runs" ;;
    null) [ "$FLEETISH" = 1 ] && warn "the login item's state could not be read" ;;
  esac
  # Gatekeeper: a canary is signed ad hoc. curl and gh leave no quarantine flag, but a zip from a browser does, and
  # then macOS refuses to open the app until a person allows it.
  if [ -d "$APP" ] && xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
    need "Gatekeeper: $APP carries a quarantine flag, and macOS will not open an app signed ad hoc with one" "xattr -dr com.apple.quarantine '$APP'"
  elif [ -d "$APP" ]; then done_ "Gatekeeper: the app carries no quarantine flag"
  fi
fi

# ---- 4. Machine checks, reported and never changed ----
FW=$("$FIREWALL" --getglobalstate 2>/dev/null || true)
case "$FW" in *enabled*|*"State = 1"*|*"State = 2"*) FW=on ;; *disabled*|*"State = 0"*) FW=off ;; *) FW=unknown ;; esac
AUTO=$(defaults read "$SWU" AutomaticallyInstallMacOSUpdates 2>/dev/null || echo unset)
case "$AUTO" in 1|true|YES) AUTO=on ;; 0|false|NO) AUTO=off ;; *) AUTO=unset ;; esac
FV=$(fdesetup status 2>/dev/null || true)
case "$FV" in *"is On"*) FV=on ;; *"is Off"*) FV=off ;; *) FV=unknown ;; esac
DSLEEP=$(fact awake.displaySleepMinutes); FREE=$(fact load.diskFreeBytes); TOTAL=$(fact load.diskTotalBytes)
NAME=$(fact identity.computerName)
[ -n "$NAME" ] && [ "$NAME" != null ] || NAME=$(scutil --get ComputerName 2>/dev/null || echo "")
if [ -z "$FREE" ] || [ "$FREE" = null ]; then
  FREE=$(df -k "$HOME" 2>/dev/null | awk 'NR == 2 { print $4 * 1024 }'); TOTAL=$(df -k "$HOME" 2>/dev/null | awk 'NR == 2 { print $2 * 1024 }')
fi
gb() { awk -v b="${1:-0}" 'BEGIN { printf "%.0f GB", b / 1e9 }'; }

[ "$FW" = off ] && warn "the firewall is off. A person turns it on in System Settings > Network > Firewall, or: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on"
if [ "$FLEETISH" = 1 ]; then
  [ "$AUTO" = off ] || warn "automatic macOS updates are $AUTO: macOS may restart this Mac on its own, and with FileVault it then waits at the login window. A person turns them off in System Settings > General > Software Update > Automatic Updates, or: sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false"
  case "$DSLEEP" in 0|""|null) ;; *) warn "the display sleeps after $DSLEEP min, and then a screen task finds no lit display unless a quiet hold keeps it awake. To keep it lit on the charger: sudo pmset -c displaysleep 0" ;; esac
  case "$NAME" in *"'s "*|*"’s "*|"") warn "the computer name, '${NAME}', is the one macOS gave it. A name of its own tells BarkBot which Mac it is: sudo scutil --set ComputerName '<name>'" ;; esac
  [ "$FV" = on ] && warn "FileVault is on: after a restart this Mac waits at the login window, offline to BarkBot, until a person types the password. No setting lets a Mac unlock itself unattended. Before each planned restart a person runs sudo fdesetup authrestart, which takes the password once and unlocks the disk at the next start only"
fi
[ -n "$FREE" ] && awk -v f="$FREE" 'BEGIN { exit !(f > 0 && f < 20e9) }' && warn "only $(gb "$FREE") free on the home volume: builds and agents need room"

# ---- 5. The report ----
lines() { printf '%s' "$1" | sed '/^$/d'; }
jstr() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$TAB/\\\\t/g")"; }
jarr() { first=1; printf '['; lines "$1" | while IFS= read -r l; do [ $first = 1 ] || printf ', '; first=0; jstr "$l"; done; printf ']'; }
jnum() { case "$1" in ''|null|*[!0-9.]*) printf 'null' ;; *) printf '%s' "$1" ;; esac; }
if [ "$JSON" = 1 ]; then
  printf '{"schema": 1, "mode": "%s", "dryRun": %s, "installed": %s, "version": %s, "canary": %s, "unattended": %s,\n' \
    "$MODE" "$([ "$DRY" = 1 ] && echo true || echo false)" "$INSTALLED" \
    "$([ -n "$HAVE" ] && jstr "$HAVE" || echo null)" "$([ -n "$CANARY" ] && jstr "$CANARY" || echo null)" "$UNATTENDED"
  printf ' "actions": %s,\n "done": %s,\n' "$(jarr "$ACTIONS")" "$(jarr "$DONE")"
  printf ' "needsPerson": ['
  first=1
  lines "$NEEDS" | { while IFS="$TAB" read -r w c; do [ $first = 1 ] || printf ', '; first=0; printf '{"what": %s, "command": %s}' "$(jstr "$w")" "$(jstr "$c")"; done; }
  printf '],\n "warnings": %s,\n' "$(jarr "$WARN")"
  printf ' "checks": {"firewall": "%s", "automaticMacOSUpdates": "%s", "fileVault": "%s", "displaySleepMinutes": %s, "diskFreeBytes": %s, "diskTotalBytes": %s, "computerName": %s}}\n' \
    "$FW" "$AUTO" "$FV" "$(jnum "$DSLEEP")" "$(jnum "$FREE")" "$(jnum "$TOTAL")" "$(jstr "$NAME")"
  exit 0
fi
echo
case "$MODE" in fleet) m="a fleet Mac" ;; dev) m="a person's own Mac" ;; *) m="a check only, nothing is changed" ;; esac
echo "MinMacs provision: $m$([ "$DRY" = 1 ] && echo ', dry run: nothing was changed')"
[ -n "$ACTIONS" ] && { [ "$DRY" = 1 ] && echo "What it would do:" || echo "What it did:"; lines "$ACTIONS" | sed 's/^/  - /'; }
[ -n "$DONE" ] && { echo "In place:"; lines "$DONE" | sed 's/^/  ok  /'; }
if [ -n "$NEEDS" ]; then
  echo "Needs a person, once:"
  lines "$NEEDS" | while IFS="$TAB" read -r w c; do printf '  - %s\n      %s\n' "$w" "$c"; done
else echo "Needs a person: nothing."; fi
[ -n "$WARN" ] && { echo "Notes:"; lines "$WARN" | sed 's/^/  ! /'; }
echo "Checks, reported and never changed:"
case "$DSLEEP" in ''|null) DS=unknown ;; 0) DS=never ;; *) DS="$DSLEEP min" ;; esac
printf '  %-26s %s\n' "Firewall" "$FW" "Automatic macOS updates" "$AUTO" "FileVault" "$FV" "Display sleep" "$DS" \
  "Free disk" "$(gb "$FREE") of $(gb "$TOTAL")" "Computer name" "${NAME:-unknown}"
exit 0
