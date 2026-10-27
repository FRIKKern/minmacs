#!/usr/bin/env python3
# Writes the git facts test/workforest/wfcli.m feeds to WorkForest, for the fixture worktrees only, until Know computes
# them itself. It reads git the way WorkForest 0.1's ReadFacts did: ancestry, the same tree, cherry and the squash
# patch-id, upstream tracking, status and the commits on no remote. It only reads; it never changes a repo.
# Usage: gitfacts.py <out.json> <worktree> ...
import json, os, subprocess, sys

def git(d, *args, stdin=None):
    r = subprocess.run(["git", "-C", d, "--no-pager"] + list(args), input=stdin, capture_output=True, text=True,
                       env=dict(os.environ, GIT_OPTIONAL_LOCKS="0", LC_ALL="C"))
    return r.returncode, r.stdout.strip()

def count(d, *args):
    st, out = git(d, "rev-list", "--count", *args)
    return int(out) if st == 0 and out.isdigit() else -1

def patch_ids(repo, ref):
    st, log = git(repo, "log", "-p", "--no-merges", "--no-color", "--no-ext-diff", "-n", "400", "--format=commit %H", ref)
    if st != 0 or not log: return set()
    _, out = git(repo, "patch-id", "--stable", stdin=log + "\n")
    return {l.split(" ")[0] for l in out.splitlines() if l}

def facts(d):
    path = os.path.realpath(d)
    f = {}
    _, f["head"] = git(path, "rev-parse", "HEAD")
    st, common = git(path, "rev-parse", "--path-format=absolute", "--git-common-dir")
    repo = os.path.dirname(common) if common.endswith("/.git") else common
    main = os.path.realpath(repo) == path
    st, d_ = git(path, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    default = d_ if st == 0 and d_ else ("origin/main" if git(path, "rev-parse", "--verify", "--quiet", "origin/main^{commit}")[0] == 0 else "main")
    f["defaultBranch"] = default
    st, branch = git(path, "symbolic-ref", "--quiet", "--short", "HEAD")
    branch = branch if st == 0 else ""
    f["upstream"], f["upstreamGone"] = "", False
    if branch:
        _, track = git(path, "for-each-ref", "--format=%(upstream:short)%1f%(upstream:track)", "refs/heads/" + branch)
        name, _, tr = track.partition("\x1f")
        f["upstream"] = name
        f["upstreamGone"] = "gone" in tr
    _, status = git(path, "status", "--porcelain=v1", "--untracked-files=normal", "--ignore-submodules=dirty")
    lines = [l for l in status.splitlines() if len(l) >= 3]
    f["untracked"] = sum(1 for l in lines if l.startswith("??"))
    f["dirty"] = len(lines) - f["untracked"]
    _, stash = git(repo, "stash", "list", "--format=%gs")
    f["stashes"] = sum(1 for s in stash.splitlines() if branch and (s.startswith("WIP on %s:" % branch) or s.startswith("On %s:" % branch)))
    f["notInDefault"] = count(path, default + "..HEAD")
    f["unpushed"] = count(path, "HEAD", "--not", default, "--remotes")
    _, remote = git(path, "branch", "-r", "--contains", "HEAD")
    f["onRemote"] = bool(remote.strip())
    merged = None
    if not main and f["notInDefault"] == 0: merged = "ancestor"
    elif not main and f["notInDefault"] > 0:
        if git(path, "diff", "--quiet", default, "HEAD", "--")[0] == 0: merged = "tree"
        else:
            st, cherry = git(path, "cherry", default, "HEAD")
            if st == 0 and cherry and "+ " not in cherry and not cherry.startswith("+"): merged = "patch"
        if not merged:
            st, base = git(path, "merge-base", default, "HEAD")
            if st == 0 and base:
                _, diff = git(path, "diff", "--no-color", "--no-ext-diff", base, "HEAD")
                _, mine = git(path, "patch-id", "--stable", stdin=diff + "\n")
                mine = mine.split(" ")[0] if mine else ""
                if mine and mine in patch_ids(repo, default): merged = "squash"
    f["merged"] = merged
    _, ct = git(path, "log", "-1", "--format=%ct", "HEAD")
    if ct.isdigit(): f["lastCommit"] = int(ct)
    return path, f

out = {}
for d in sys.argv[2:]:
    if os.path.isdir(d):
        p, f = facts(d)
        out[p] = f
json.dump(out, open(sys.argv[1], "w"), indent=1, sort_keys=True)
