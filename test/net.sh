# Network and volume facts, wave 7. Sourced by test.sh after core, which built $APP.
# test/net/nettool.m links all of Sources/Core with -DMM_TESTS and checks MMNet.h on fake readings: counters that
# wrap or go back, an interface that goes away and comes back, a VPN tunnel, and no primary route.
# One check reads the real counters and route, through the release binary's net verb, and asks only that they parse.
# This section starts no process but its own tool and the binary, and writes only inside $MINMACS_HOME.

nt_dir="$MINMACS_HOME/net.$$"
mkdir -p "$nt_dir"
nt_tool="$nt_dir/nettool"
clang -fobjc-arc -O2 -mmacosx-version-min=14.0 -arch arm64 -arch x86_64 -ISources -DMM_TESTS \
  -Wall -Wextra -Wno-unused-parameter -Werror \
  $(find Sources/Core -name '*.m' | LC_ALL=C sort) test/net/nettool.m \
  -framework Cocoa -framework IOKit -framework UserNotifications -lsqlite3 -o "$nt_tool" >"$nt_dir/clang.log" 2>&1
nt_r=$?
check "net: the tool builds with MM_TESTS and no warnings" 0 "$nt_r"
[ "$nt_r" = 0 ] || tail -20 "$nt_dir/clang.log"
check "net: SystemConfiguration links from the object file" yes "$(otool -L "$nt_tool" 2>/dev/null | grep -q SystemConfiguration.framework && echo yes)"

nt_out=$("$nt_tool" steps 2>"$nt_dir/steps.err")
nj() { printf '%s' "$nt_out" | json "$1" 2>/dev/null; }
check "net: loopback is left out of the interfaces" "bridge0,en0,en5,utun3" "$(nj 'j["first"]["names"]')"
check "net: the whole Mac counts physical interfaces only" "1100 2100" "$(nj '"%d %d" % (j["first"]["in"], j["first"]["out"])')"
check "net: a tunnel is counted apart" 300 "$(nj 'j["first"]["tunnelIn"]')"
check "net: the first reading has no rate" "None 0 None" "$(nj '"%s %s %s" % (j["first"]["rateIn"], j["first"]["rateSeconds"], j["first"]["ifRate"])')"
check "net: the route names its interface and kind" "True wifi en0" "$(nj '"%s %s %s" % (j["first"]["online"], j["first"]["kind"], j["first"]["primary"])')"
check "net: a step gives bytes a second" "1000 2000 5" "$(nj '"%s %s %s" % (j["step"]["in"], j["step"]["out"], j["step"]["seconds"])')"
check "net: a VPN does not count its traffic twice" "1000 800" "$(nj '"%s %s" % (j["step"]["in"], j["step"]["tunnelIn"])')"
check "net: a bridge has its rate but stays out of the sum" "400 virtual" "$(nj '"%s %s" % (j["step"]["ifs"]["bridge0"]["in"], j["step"]["ifs"]["bridge0"]["group"])')"
check "net: a 32-bit counter that wraps gives its true step" "259 False" "$(nj '"%s %s" % (j["wrap"]["in"], j["wrap"]["reset"])')"
check "net: a counter that goes back counts 0, not negative" "0 0 True" "$(nj '"%s %s %s" % (j["back"]["in"], j["back"]["out"], j["back"]["reset"])')"
check "net: a 64-bit counter that drops from 3.5 GB is a reset, not a 32-bit wrap" "0 True" "$(nj '"%s %s" % (j["wide"]["in"], j["wide"]["reset"])')"
check "net: a 64-bit counter wraps at 64 bits" "400 False" "$(nj '"%s %s" % (j["wrap64"]["in"], j["wrap64"]["reset"])')"
check "net: a low counter that goes back is a reset" "0 True" "$(nj '"%s %s" % (j["lowBack"]["in"], j["lowBack"]["reset"])')"
check "net: a step past 100 Gbit/s counts 0" "0 True" "$(nj '"%s %s" % (j["huge"]["in"], j["huge"]["reset"])')"
check "net: a link's own speed bounds its step" "0 100000000" "$(nj '"%s %s" % (j["baud"]["over"], j["baud"]["under"])')"
check "net: a gone interface leaves the list and the sum" "en0,utun3 11000 1000" "$(nj '"%s %s %s" % (j["gone"]["names"], j["gone"]["in"], j["gone"]["rateIn"])')"
check "net: an interface that comes back counts 0 at first" "0 1000 100" "$(nj '"%s %s %s" % (j["back5"]["en5"], j["back5"]["rateIn"], j["back5"]["next"])')"
check "net: offline has no primary route" "False none None null" "$(nj '"%s %s %s %s" % (j["offline"]["online"], j["offline"]["kind"], j["offline"]["primary"], j["offline"]["json"])')"
check "net: the same clock twice gives no rate" "None 0" "$(nj '"%s %s" % (j["sameClock"]["in"], j["sameClock"]["seconds"])')"
check "net: Wi-Fi, Ethernet and a phone are told apart" "wifi ethernet phone phone" "$(nj '" ".join(j["kinds"][k] for k in ("wifi", "ethernet", "iphone", "bluetooth"))')"
check "net: a tunnel, a bridge, an unlisted name and none" "tunnel other other none" "$(nj '" ".join(j["kinds"][k] for k in ("utun", "bridge", "unlisted", "none"))')"
check "net: the JSON form has its keys" "bytesIn,bytesOut,inPerSecond,interfaces,kind,online,outPerSecond,primaryInterface,rateSeconds,tunnel" "$(nj 'j["json"]["keys"]')"
check "net: an unknown rate is null in JSON" null "$(nj 'j["json"]["firstRate"]')"

nt_out=$("$nt_tool" senses 2>"$nt_dir/senses.err")
check "net: the Senses pass reads the fake reader" "phone en7 True" "$(nj '"%s %s %s" % (j["kind"], j["primary"], j["online"])')"
check "net: two passes give the rate on the power sheet" "None 1000 250 500" "$(nj '"%s %s %s %s" % (j["firstRate"], j["in"], j["out"], j["tunnelIn"])')"
check "net: a pass with every interface gone and no route" "False 0 0" "$(nj '"%s %s %s" % (j["emptyOnline"], j["emptyIn"], j["emptyCount"])')"
check "net: the home volume's size sits beside its free bytes" True "$(nj 'j["diskTotal"]')"
check "net: the pass times the network apart" "True True" "$(nj '"%s %s" % (j["netNs"], j["partsSum"])')"

# Where it runs: the Senses pass only, so no menu, card or expert reads the network itself.
check "net: only Senses reads the network" "Sources/Core/Senses/MMSenses.m" "$(grep -rl 'MMNetRead(' Sources --include='*.m' | grep -v 'Senses/MMNet.m' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
check "net: MMNet uses no AppKit" 0 "$(grep -cE '#import <(AppKit|Cocoa)' Sources/Core/Senses/MMNet.m)"
check "net: the release build has no fake net source" 0 "$(nm "$BIN" 2>/dev/null | grep -c MMUseNetSource)"

# The real counters and route, once, through the release binary. Only that they parse.
MINMACS_HOME="$nt_dir/cli" "$BIN" net --json >"$nt_dir/real.json" 2>"$nt_dir/real.err"
check "net: net --json exits 0" 0 "$?"
nr() { json "$1" <"$nt_dir/real.json" 2>/dev/null; }
check "net: the real counters parse" yes "$(nr '"yes" if j["net"]["interfaces"] and all(isinstance(i["bytesIn"], int) and i["bytesIn"] >= 0 and i["group"] in ("physical", "tunnel", "virtual") for i in j["net"]["interfaces"]) else j["net"]')"
check "net: the real reading leaves loopback out" 0 "$(nr 'sum(1 for i in j["net"]["interfaces"] if i["name"].startswith("lo"))')"
check "net: the real rates are null or not negative" yes "$(nr '"yes" if all(v is None or v >= 0 for v in [j["net"]["inPerSecond"], j["net"]["outPerSecond"]] + [i[k] for i in j["net"]["interfaces"] for k in ("inPerSecond", "outPerSecond")]) else "no"')"
check "net: the real route parses" yes "$(nr '"yes" if isinstance(j["net"]["online"], bool) and j["net"]["kind"] in ("none", "wifi", "ethernet", "phone", "tunnel", "other") and (j["net"]["primaryInterface"] is None) != j["net"]["online"] else j["net"]["kind"]')"
check "net: the real volume parses" yes "$(nr '"yes" if j["volume"]["totalBytes"] >= j["volume"]["freeBytes"] > 0 else j["volume"]')"
MINMACS_HOME="$nt_dir/cli" "$BIN" status --json >"$nt_dir/status.json" 2>"$nt_dir/status.err"
check "net: status --json carries net and volume" "True True" "$(json '"%s %s" % (isinstance(j["net"], dict), j["volume"]["totalBytes"] > 0)' <"$nt_dir/status.json" 2>/dev/null)"
check "net: the net verb says the route in words" 1 "$(MINMACS_HOME="$nt_dir/cli" "$BIN" net 2>/dev/null | grep -cE '^(Online over |Offline: no primary route)')"
