# ===== device: what this Mac can take on now, for a remote orchestrator, D9 part 2 =====
# Sourced by test.sh after core. The built binary reads this Mac once, read only, and its JSON must have the shape
# docs/CLI.md gives. The fixture cases run test/quiet/tool.m under -DMM_TESTS, with a fake power source and fake
# displays, so the lid, power and display cases need no change to this Mac. Nothing here starts or stops a process
# but the tool, and nothing reads the person's prefs: every run has a MINMACS_HOME of its own.
. ./test/quiet/build.sh
dv="$MINMACS_HOME/device.$$"
mkdir -p "$dv/cli"

echo "-- the built binary, read once, no app"
MINMACS_HOME="$dv/cli" MINMACS_COLD=1 "$BIN" device --json >"$dv/real.json" 2>"$dv/real.err"
check "device: --json exits 0 with no app" 0 "$?"
check "device: every field has its type" ok "$(python3 -I test/device/shape.py <"$dv/real.json" | head -5 | tr '\n' ' ' | sed 's/ $//')"
check "device: it says no app answered" False "$(json "j['inApp']" <"$dv/real.json")"
check "device: the MinMacs version is the bundle's" "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist) $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)" \
  "$(json "j['identity']['minmacs']['version'] + ' ' + str(j['identity']['minmacs']['build'])" <"$dv/real.json")"
check "device: the memory size is the kernel's" "$(sysctl -n hw.memsize)" "$(json "j['identity']['memoryBytes']" <"$dv/real.json")"
check "device: the chip is the kernel's" "$(sysctl -n machdep.cpu.brand_string)" "$(json "j['identity']['chip']" <"$dv/real.json")"
check "device: the lid is IOKit's" "$(ioreg -r -k AppleClamshellState -d 1 2>/dev/null | grep -q '"AppleClamshellState" = Yes' && echo True || echo False)" \
  "$(json "j['lid']['closed']" <"$dv/real.json")"
check "device: no quiet hold in a fresh home" False "$(json "j['quiet']['active']" <"$dv/real.json")"
MINMACS_HOME="$dv/cli" MINMACS_COLD=1 "$BIN" device >"$dv/real.txt" 2>&1
check "device: the plain form exits 0 and names the display" yes "$(grep -q '^Display: ' "$dv/real.txt" && echo yes || echo no)"
MINMACS_HOME="$dv/cli" MINMACS_COLD=1 "$BIN" device extra >/dev/null 2>&1
check "device: an extra word is a usage error" 2 "$?"

echo "-- what it reads: no process, no pmset, nothing on a tick"
check "device: the verb and the display sense run no process" 0 \
  "$(grep -nE 'NSTask|posix_spawn|popen\(|system\(|MMRun\(|"/usr/bin/pmset"|"pmset"|"lsof"|"/bin/ps"' Sources/CLI/MMDeviceCLI.m Sources/Core/Senses/MMDisplay.m | grep -c .)"
check "device: no tick reads the displays" 0 "$(grep -n 'MMDisplaysNow' Sources/Core/Senses/MMSenses.m Sources/Core/Graph/*.m Sources/Core/MMCore.m | grep -c .)"
check "device: the release binary has no fake displays" 0 "$(nm "$BIN" 2>/dev/null | grep -c 'MMUseDisplays')"

echo "-- the fixture cases, fake power and displays"
dv_case() { # name, facts JSON: prints the device JSON into $dv/<name>.json
  printf '%s\n' "$2" >"$dv/$1.facts"
  mkdir -p "$dv/home-$1"
  MINMACS_HOME="$dv/home-$1" "$DQ" device "$dv/$1.facts" >"$dv/$1.json" 2>"$dv/$1.err"
}
dv_get() { json "$2" <"$dv/$1.json"; }
DV_IN='{"builtin": true, "asleep": false, "active": true, "main": true, "displayID": 1, "width": 1710, "height": 1107, "vendor": 1552, "model": 41060}'
DV_EXT='{"builtin": false, "asleep": false, "active": true, "main": false, "displayID": 7, "width": 1920, "height": 1080, "vendor": 9999, "model": 1}'
DV_IN_ASLEEP='{"builtin": true, "asleep": true, "active": true, "main": true, "displayID": 1}'

dv_case open '{"power": {"onAC": false, "batteryPercent": 55, "lowPowerMode": true, "thermal": 2, "memoryPressure": 4, "diskFree": 1000, "diskTotal": 2000}, "displays": ['"$DV_IN"']}'
check "device: the fixture run exits with a report" ok "$(python3 -I test/device/shape.py <"$dv/open.json" | head -5 | tr '\n' ' ' | sed 's/ $//')"
check "device: on battery, as the power source says" "False 55 True serious" \
  "$(dv_get open "'%s %s %s %s' % (j['power']['onAC'], j['power']['batteryPercent'], j['power']['lowPowerMode'], j['power']['thermal'])")"
check "device: memory pressure and disk from the same facts" "critical 1000 2000" \
  "$(dv_get open "'%s %s %s' % (j['load']['memoryPressure'], j['load']['diskFreeBytes'], j['load']['diskTotalBytes'])")"
check "device: lid open, built-in awake: it can capture" "builtin True" "$(dv_get open "'%s %s' % (j['display']['active'], j['display']['canCaptureScreen'])")"
check "device: the display is listed" "1 True 1710" "$(dv_get open "'%d %s %d' % (len(j['display']['displays']), j['display']['displays'][0]['builtin'], j['display']['displays'][0]['width'])")"
check "device: in the app it reads its own cost" True "$(dv_get open "j['inApp'] and isinstance(j['minmacs'], dict) and j['minmacs']['memory']['footprintBytes'] > 0")"

dv_case nobattery '{"power": {"onAC": true, "batteryPercent": -1}, "displays": ['"$DV_IN"']}'
check "device: no battery is null" "True None" "$(dv_get nobattery "'%s %s' % (j['power']['onAC'], j['power']['batteryPercent'])")"

dv_case shut '{"power": {"lidClosed": true}, "displays": ['"$DV_IN"']}'
check "device: lid shut, built-in only: no screen" "none False True" "$(dv_get shut "'%s %s %s' % (j['display']['active'], j['display']['canCaptureScreen'], j['lid']['closed'])")"

dv_case lidmode '{"power": {"lidClosed": true, "lidOverride": true}, "displays": ['"$DV_IN"'], "prefs": {"insomnia.lid": true, "insomnia.lid.screenOff": false}}'
check "device: lid mode live, screen left on: the panel stays lit" "builtin True" "$(dv_get lidmode "'%s %s' % (j['display']['active'], j['display']['canCaptureScreen'])")"
check "device: and the lid says so" "True True False True" \
  "$(dv_get lidmode "'%s %s %s %s' % (j['lid']['insomniaLidMode'], j['lid']['insomniaLidLive'], j['lid']['screenOff'], j['lid']['keepsScreenLit'])")"

dv_case screenoff '{"power": {"lidClosed": true, "lidOverride": true}, "displays": ['"$DV_IN"'], "prefs": {"insomnia.lid": true}}'
check "device: lid mode live, screen off: no screen" "none False False" "$(dv_get screenoff "'%s %s %s' % (j['display']['active'], j['display']['canCaptureScreen'], j['lid']['keepsScreenLit'])")"

dv_case notlive '{"power": {"lidClosed": true, "lidOverride": false}, "displays": ['"$DV_IN"'], "prefs": {"insomnia.lid": true, "insomnia.lid.screenOff": false}}'
check "device: lid mode on but not live: no screen" "False False" "$(dv_get notlive "'%s %s' % (j['display']['canCaptureScreen'], j['lid']['insomniaLidLive'])")"

dv_case external '{"power": {"lidClosed": true}, "displays": ['"$DV_IN"', '"$DV_EXT"']}'
check "device: lid shut with an external display awake: it can capture" "external True True" \
  "$(dv_get external "'%s %s %s' % (j['display']['active'], j['display']['canCaptureScreen'], j['display']['externalAwake'])")"

dv_case asleep '{"power": {"lidClosed": false}, "displays": ['"$DV_IN_ASLEEP"']}'
check "device: the display asleep: no capture" "asleep False" "$(dv_get asleep "'%s %s' % (j['display']['active'], j['display']['canCaptureScreen'])")"

dv_case nodisplay '{"power": {}, "displays": []}'
check "device: no display at all: none" "none False True" "$(dv_get nodisplay "'%s %s %s' % (j['display']['active'], j['display']['canCaptureScreen'], j['display']['known'])")"

dv_case manual '{"power": {}, "displays": [], "prefs": {"insomnia.awake": true, "insomnia.agents": false}}'
check "device: Keep Mac Awake and the agents switch are read from the prefs" "True False" "$(dv_get manual "'%s %s' % (j['awake']['manual'], j['awake']['agentsMode'])")"
# ===== end of device =====
