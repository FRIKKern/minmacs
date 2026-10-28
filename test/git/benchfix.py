#!/usr/bin/env python3
"""Makes the bench fixture: repos with a long default branch and linked worktrees, under one roots folder.

Usage: benchfix.py <roots> <repos> <commits> [jobs]
jobs repos are made at a time, 1 by default. tools/bench and test/bench.sh make 30 repos, 300 checkouts, 8 at a time.
Each repo gets <commits> commits on main through git fast-import, then 9 linked worktrees in <roots>/wt:
  1, 2   branches at old main commits, merged by ancestry
  3      a branch of two commits, squash-merged into main
  4      a branch of one commit, cherry-picked into main
  5 to 9 open branches of 1 to 5 commits, and worktree 9 has a changed file and an untracked one
Main then gets two more commits, so no branch is merged by tree. Paths are printed as JSON.
The caller sets GIT_CONFIG_GLOBAL and the author, so the person's git config stays out.
"""
import json
import os
import subprocess
import sys

from concurrent.futures import ThreadPoolExecutor

roots, repos, commits = os.path.abspath(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
jobs = int(sys.argv[4]) if len(sys.argv) > 4 else 1


def git(cwd, *args, stdin=None):
    subprocess.run(["git", "-c", "init.defaultBranch=main", "-c", "advice.detachedHead=false", *args], cwd=cwd,
                   input=stdin, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def commit_file(cwd, name, text, msg):
    with open(os.path.join(cwd, name), "a") as f:
        f.write(text)
    git(cwd, "add", name)
    git(cwd, "commit", "-q", "-m", msg)


def history(n):
    """A fast-import stream of n commits on main, each adding a line to one of 20 files."""
    out, files = [], {}
    for i in range(n):
        name = "f%d.txt" % (i % 20)
        files[name] = files.get(name, "") + "commit %d\n" % i
        msg = "main %d\n" % i
        body = files[name].encode()
        out.append(b"commit refs/heads/main\nmark :%d\n" % (i + 1))
        out.append(b"committer fixture <fixture@example.invalid> %d +0000\n" % (1700000000 + i * 60))
        out.append(b"data %d\n%s" % (len(msg), msg.encode()))
        if i:
            out.append(b"from :%d\n" % i)
        out.append(b"M 644 inline %s\ndata %d\n%s\n" % (name.encode(), len(body), body))
    return b"".join(out)


os.makedirs(os.path.join(roots, "wt"), exist_ok=True)
stream = history(commits)


def make(k):
    """One repo and its 9 worktrees. Returns the repo's path and its 10 checkouts."""
    repo = os.path.join(roots, "r%d" % k)
    git(roots, "init", "-q", repo)
    git(repo, "fast-import", "--quiet", stdin=stream)
    git(repo, "reset", "-q", "--hard", "main")
    wt = lambda j: os.path.join(roots, "wt", "r%d-%d" % (k, j))
    git(repo, "worktree", "add", "-q", "-b", "a1", wt(1), "main~100")
    git(repo, "worktree", "add", "-q", "-b", "a2", wt(2), "main~10")
    git(repo, "worktree", "add", "-q", "-b", "s3", wt(3), "main~40")
    commit_file(wt(3), "s3a.txt", "squash a\n", "s3 a")
    commit_file(wt(3), "s3b.txt", "squash b\n", "s3 b")
    git(repo, "worktree", "add", "-q", "-b", "p4", wt(4), "main~30")
    commit_file(wt(4), "p4.txt", "picked\n", "p4")
    for j in range(5, 10):
        git(repo, "worktree", "add", "-q", "-b", "o%d" % j, wt(j), "main~%d" % (j * 20))
        for c in range(j - 4):
            commit_file(wt(j), "o%d.txt" % j, "open %d\n" % c, "o%d %d" % (j, c))
    git(repo, "merge", "-q", "--squash", "s3")
    git(repo, "commit", "-q", "-m", "squash s3")
    git(repo, "cherry-pick", "p4")
    commit_file(repo, "after.txt", "after 1\n", "after 1")
    commit_file(repo, "after.txt", "after 2\n", "after 2")
    with open(os.path.join(wt(9), "f0.txt"), "a") as f:
        f.write("changed\n")
    with open(os.path.join(wt(9), "new.txt"), "w") as f:
        f.write("untracked\n")
    return repo, [repo] + [wt(j) for j in range(1, 10)]


made = {"repos": [], "worktrees": []}
with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
    for repo, trees in pool.map(make, range(repos)):
        made["repos"].append(repo)
        made["worktrees"] += trees
print(json.dumps(made))
