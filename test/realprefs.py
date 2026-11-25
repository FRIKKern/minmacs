# The backstop on the person's own prefs plist, run by test.sh around each section. It only ever reads that file.
#   realprefs.py snap <plist> <out.json>          the plist's keys and values, its mtime and size, and whether an
#                                                 installed MinMacs runs, as JSON
#   realprefs.py diff <before.json> <after.json>  one line: "fail <why>", "note <why>" or "same"
# The rule. The installed app writes this file whenever the person presses something, so a change alone proves
# nothing. A change fails when it cannot be the app's:
#   1. a key appeared or changed whose name only tests use: test.*, wire.*, store.*, or
#   2. the file changed while no installed MinMacs ran, neither at the start nor at the end of the section.
# Any other change is a note line that names the keys, so it stays visible.
import json, os, plistlib, subprocess, sys

TEST_ONLY = ("test.", "wire.", "store.")
APPS = [os.path.expanduser("~/Applications/MinMacs.app/Contents/MacOS/MinMacs"), "/Applications/MinMacs.app/Contents/MacOS/MinMacs"]


def app_runs():
    # Reads the process list only, to tell the app's own writes from a test's. It never signals anything.
    out = subprocess.run(["/bin/ps", "-axo", "args="], capture_output=True, text=True).stdout.splitlines()
    return any(line.strip() in APPS for line in out)


def snap(plist, out):
    keys, stamp = {}, "none"
    try:
        st = os.stat(plist)
        stamp = "%d %d" % (int(st.st_mtime), st.st_size)
        with open(plist, "rb") as f:
            keys = {k: repr(v) for k, v in plistlib.load(f).items()}
    except (OSError, plistlib.InvalidFileException, ValueError):
        pass
    with open(out, "w") as f:
        json.dump({"stamp": stamp, "keys": keys, "app": app_runs()}, f)


def diff(a, b):
    with open(a) as f: x = json.load(f)
    with open(b) as f: y = json.load(f)
    if x["stamp"] == y["stamp"] and x["keys"] == y["keys"]:
        return "same"
    changed = sorted(k for k in set(x["keys"]) | set(y["keys"]) if x["keys"].get(k) != y["keys"].get(k))
    test_keys = [k for k in changed if k.startswith(TEST_ONLY)]
    if test_keys:
        return "fail a key only tests use: " + " ".join(test_keys)
    if not (x["app"] or y["app"]):
        return "fail it changed while no installed MinMacs ran: " + (" ".join(changed) or y["stamp"])
    return "note the installed app may have written it: " + (" ".join(changed) or "no key changed")


if __name__ == "__main__":
    if sys.argv[1] == "snap":
        snap(sys.argv[2], sys.argv[3])
    else:
        print(diff(sys.argv[2], sys.argv[3]))
