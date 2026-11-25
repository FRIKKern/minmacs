#!/usr/bin/env python3
"""The field's idle in a fixture home, for `bench idle`. Issue #52.

The owner's Mac on 2026-11-25, with the window closed: many Claude Code sessions at work, each appending to its
transcript about once a second, one transcript of 36 MB, about 15 worktrees over several repos, 665 Claude Code
scratch folders that the clutter scan holds as live, and an undo log of about 400 records (`bench seed` writes it).

  fieldfix.py make <home> [--repos N] [--worktrees N] [--transcripts N] [--big-mb N] [--scratch N]
  fieldfix.py run <home> --seconds S [--agents N] [--every S]

`make` writes, all inside <home>:
  roots/repoR, a git repo with one commit, and roots/repoR-wt/wW, its linked worktrees;
  claude/projects/<folder>/<id>.jsonl, the transcripts, the third, the first from roots/, of --big-mb, a few of 4 to 8 MB, the rest small;
  clutter/private/tmp/claude-501/<folder>/<id>/scratchpad, the scratch folders, written a minute ago.

`run` plays the agents for S seconds: N shells of its own, each a session's pid with its status file in
claude/sessions, working in a worktree, where it starts a short-lived child every 2 seconds, as an agent's tools do.
Every --every seconds each working session appends a tool use and its result to its transcript. Every 15 seconds an edit lands in a worktree, written beside and renamed over, as an editor
saves; every 3 seconds a short-lived process runs in one; every 20 seconds one session goes idle or back to work.
It stops only the processes it started, and removes its status files at the end.
"""
import json, os, random, signal, subprocess, sys, time, uuid

def arg(name, default):
    a = sys.argv
    return type(default)(a[a.index(name) + 1]) if name in a else default

def git(cwd, *args):
    env = dict(os.environ, GIT_CONFIG_GLOBAL=os.path.join(HOME, "gitconfig"), GIT_CONFIG_NOSYSTEM="1",
               GIT_AUTHOR_NAME="fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
               GIT_COMMITTER_NAME="fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid")
    subprocess.run(["git", *args], cwd=cwd, env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def stamp(t=None):
    t = time.time() if t is None else t
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int((t % 1) * 1000)

def tool_lines(cwd, sid, t):
    """One Edit and its result, about 1.5 KB, as an agent at work writes them."""
    tid = "toolu_" + uuid.uuid4().hex[:20]
    edit = {"type": "assistant", "sessionId": sid, "cwd": cwd, "timestamp": stamp(t), "uuid": str(uuid.uuid4()),
            "message": {"role": "assistant", "content": [{"type": "tool_use", "id": tid, "name": "Edit",
                        "input": {"file_path": cwd + "/Sources/main.m", "old_string": "x" * 300, "new_string": "y" * 300}}]}}
    result = {"type": "user", "sessionId": sid, "cwd": cwd, "timestamp": stamp(t), "uuid": str(uuid.uuid4()),
              "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": tid, "content": "The file has been updated. " + "z" * 400}]}}
    return json.dumps(edit) + "\n" + json.dumps(result) + "\n"

def layout(home):
    with open(os.path.join(home, "fieldfix.json")) as f: return json.load(f)

def make(home):
    repos, per = arg("--repos", 4), arg("--worktrees", 4)
    count, big, scratch = arg("--transcripts", 40), arg("--big-mb", 36), arg("--scratch", 650)
    roots = os.path.join(home, "roots")
    os.makedirs(roots, exist_ok=True)
    open(os.path.join(home, "gitconfig"), "a").close()
    trees = []
    for r in range(repos):
        main = os.path.join(roots, "repo%d" % r)
        os.makedirs(os.path.join(main, "Sources"), exist_ok=True)
        with open(os.path.join(main, "Sources", "main.m"), "w") as f: f.write("int main(void) { return 0; }\n")
        git(main, "init", "-q", "-b", "main"); git(main, "add", "-A"); git(main, "commit", "-q", "-m", "first")
        trees.append(main)
        for w in range(per):
            wt = os.path.join(roots, "repo%d-wt" % r, "w%d" % w)
            git(main, "worktree", "add", "-q", "-b", "work-%d" % w, wt)
            trees.append(wt)
    # Transcripts: two sessions started inside a worktree, the rest in roots/, above every checkout, as on the owner's
    # Mac, where every session starts in the home folder. Codex's and pi's folders are there and quiet, so the session
    # watch watches only these, as there, where neither exists and the home folder is never watched.
    claude = os.path.join(home, "claude")
    for d in ("codex", "pi"): os.makedirs(os.path.join(home, d), exist_ok=True)
    sessions = []
    rnd = random.Random(52)
    for i in range(count):
        cwd = trees[1 + i] if i < 2 else roots
        sid = str(uuid.UUID(int=rnd.getrandbits(128)))
        folder = os.path.join(claude, "projects", cwd.replace("/", "-"))
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, sid + ".jsonl")
        mb = big if i == 2 else rnd.uniform(4, 8) if i < 5 else rnd.uniform(0.05, 0.5)
        t0 = time.time() - 3 * 3600
        with open(path, "w") as f:
            f.write(json.dumps({"type": "user", "sessionId": sid, "cwd": cwd, "gitBranch": "main", "timestamp": stamp(t0),
                                "message": {"role": "user", "content": "fixture session %d" % i}}) + "\n")
            f.write(json.dumps({"type": "ai-title", "aiTitle": "Fixture session %d" % i}) + "\n")
            block, written, n = tool_lines(cwd, sid, t0), 0, 0
            while written < mb * 1048576:
                f.write(block); written += len(block); n += 1
        sessions.append({"id": sid, "cwd": cwd, "transcript": path})
    # Scratch folders, written a minute ago, so the scan holds each as live.
    tmp = os.path.join(home, "clutter", "private", "tmp", "claude-501")
    os.makedirs(os.path.join(home, "clutter", "home"), exist_ok=True)
    for i in range(scratch):
        d = os.path.join(tmp, "-fixture-project-%d" % (i % 25), str(uuid.UUID(int=rnd.getrandbits(128))), "scratchpad")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "notes.txt"), "w") as f: f.write("scratch %d\n" % i)
    with open(os.path.join(home, "fieldfix.json"), "w") as f:
        json.dump({"roots": roots, "trees": trees, "sessions": sessions, "claude": claude}, f, indent=1)
    print(json.dumps({"worktrees": len(trees) - repos, "repos": repos, "transcripts": count, "bigMB": big, "scratch": scratch}))

def run(home):
    seconds, agents, every = arg("--seconds", 300.0), arg("--agents", 8), arg("--every", 1.0)
    lay = layout(home)
    trees = [t for t in lay["trees"]]
    sdir = os.path.join(lay["claude"], "sessions")
    os.makedirs(sdir, exist_ok=True)
    # The working sessions: the two inside a worktree, then the big one and the rest from roots/.
    working = lay["sessions"][:agents]
    procs, status = [], {}
    rnd = random.Random(os.getpid())
    for k, s in enumerate(working):
        where = s["cwd"] if s["cwd"] != lay["roots"] else trees[3 + k % (len(trees) - 3)]
        loop = "end=$(( $(date +%%s) + %d )); while [ $(date +%%s) -lt $end ]; do sleep 2; done" % (int(seconds) + 120)
        p = subprocess.Popen(["/bin/sh", "-c", loop], cwd=where, start_new_session=True)
        procs.append(p)
        s["pid"], s["status"] = p.pid, "busy"
        status[p.pid] = os.path.join(sdir, "%d.json" % p.pid)
    def write_status(s):
        body = {"pid": s["pid"], "sessionId": s["id"], "cwd": s["cwd"], "startedAt": int((time.time() - 3600) * 1000),
                "statusUpdatedAt": int(time.time() * 1000), "status": s["status"]}
        tmp = status[s["pid"]] + ".tmp"
        with open(tmp, "w") as f: json.dump(body, f)
        os.rename(tmp, status[s["pid"]])
    for s in working: write_status(s)
    def stop(*_):
        for p in procs:
            if p.poll() is None: p.terminate()
        for p in procs:
            try: p.wait(5)
            except Exception: pass
        for path in status.values():
            try: os.unlink(path)
            except FileNotFoundError: pass
        sys.exit(0)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    end, tick, edits = time.time() + seconds, 0, 0
    while time.time() < end:
        t = time.time()
        for s in working:
            if s["status"] != "busy": continue
            with open(s["transcript"], "a") as f: f.write(tool_lines(s["cwd"], s["id"], t))
        if tick % 15 == 0:
            wt = rnd.choice(trees)
            path = os.path.join(wt, "Sources", "main.m")
            with open(path + ".tmp", "w") as f: f.write("int main(void) { return %d; }\n" % edits)
            os.rename(path + ".tmp", path)
            edits += 1
        if tick % 3 == 0:
            subprocess.Popen(["/bin/sh", "-c", "sleep 0.3"], cwd=rnd.choice(trees)).wait()
        if tick % 20 == 10:
            s = rnd.choice(working)
            s["status"] = "idle" if s["status"] == "busy" else "busy"
            write_status(s)
        tick += 1
        time.sleep(max(0.0, every - (time.time() - t)))
    stop()

if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("make", "run"):
        print(__doc__, file=sys.stderr); sys.exit(2)
    HOME = os.path.abspath(sys.argv[2])
    (make if sys.argv[1] == "make" else run)(HOME)
