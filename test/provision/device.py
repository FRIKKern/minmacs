# Writes a fixture Mac's device --json for test/provision.sh: the shape of docs/cli/device.md, with the provision,
# lid, awake and load fields provision reads set from the words given, key=value.
import json, sys
out, *words = sys.argv[1:]
kv = dict(w.split("=", 1) for w in words)
b = lambda k, d: kv.get(k, d) == "true"
j = {"schema": 1, "at": 1795506021, "inApp": b("inApp", "true"),
     "identity": {"computerName": kv.get("name", "Fleet 07"), "localHostName": "Fleet-07", "model": "Mac17,4", "chip": "Apple M5",
                  "minmacs": {"version": kv.get("version", "2.0.0"), "build": kv.get("build", "2.0.0+abc1234")}},
     "lid": {"closed": False, "insomniaLidMode": b("lidMode", "false"), "insomniaLidLive": False,
             "screenOff": b("screenOff", "true"), "keepsScreenLit": False},
     "awake": {"agentsMode": b("agents", "true"), "displaySleepMinutes": int(kv.get("displaySleep", "0"))},
     "load": {"diskFreeBytes": int(kv.get("free", "500000000000")), "diskTotalBytes": 994610155520},
     "provision": {"unattended": b("unattended", "false"), "lidRuleInstalled": b("lidRule", "false"),
                   "notificationsAuthorized": {"true": True, "false": False}.get(kv.get("notifications", "true")),
                   "loginItem": kv.get("login", "enabled"), "needsPerson": []}}
json.dump(j, open(out, "w"), indent=2)
