#!/usr/bin/env python3
# Writes docs/CLI.md from `help --json` of the built binary, under each of its program names.
# Usage: python3 -I test/docs/clidoc.py <path to MinMacs binary> [repo root]   prints the page on stdout
# test/docs.sh runs it and checks that docs/CLI.md matches, so the page cannot drift from the verb registry.
# It runs the binary only for help, with MINMACS_HOME in a fresh temp folder, so it reads no real state.
import json, os, re, subprocess, sys, tempfile

PROGRAMS = ["minmacs", "locohost", "workforest", "noo-noo", "insomnia"]
SECTIONS = {"locohost": "LocoHost", "workforest": "WorkForest", "noo-noo": "Noo-Noo", "insomnia": "Insomnia"}


def help_of(binary, program, home):
    link = os.path.join(home, "bin", program)
    if not os.path.lexists(link):
        os.symlink(binary, link)
    env = dict(os.environ, MINMACS_HOME=home)
    out = subprocess.run([link, "help", "--json"], env=env, capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        sys.exit("%s help --json exited %d: %s" % (program, out.returncode, out.stderr.strip()))
    return json.loads(out.stdout)


def split_usage(usage):
    """The usage and its description. Core verbs part them with three spaces, LocoHost's with a colon."""
    m = re.match(r"^(.*?\S)\s{3,}(\S.*)$", usage)
    if m:
        return m.group(1), m.group(2)
    m = re.match(r"^(.*?[\w\]>]):\s(\S.*)$", usage)
    if m:
        return m.group(1), m.group(2)
    return usage, ""


def flags(usage):
    seen = []
    for f in re.findall(r"(?<![\w-])--[a-z][a-z-]*", usage):
        if f not in seen:
            seen.append(f)
    return seen


def exit_codes(root):
    codes = []
    text = open(os.path.join(root, "Sources", "CLI", "MMArgs.h")).read()
    for name, num, note in re.findall(r"(MMExit\w+)\s*=\s*(\d+),?\s*(?://\s*(.*))?", text):
        codes.append((int(num), name, note.strip()))
    return codes


def aliases(root):
    """The 1.x commands of MMLegacyWords in Sources/CLI/MMCLI.m, per program, as (old, new words)."""
    text = open(os.path.join(root, "Sources", "CLI", "MMCLI.m")).read()
    out = {}
    for program, body in re.findall(r"\n\s*(\w+) = @\{(.*?)\n\s*\};", text, re.S):
        rows = []
        for old, words in re.findall(r'@"([\w-]+)":\s*@\[(.*?)\]', body):
            rows.append((old, " ".join(re.findall(r'@"([^"]*)"', words)).replace("$1", "<arg>")))
        out[program] = rows
    if sorted(out) != ["locohost", "minmacs", "workforest"]:
        sys.exit("the alias tables in MMCLI.m moved: found %s" % sorted(out))
    return out


def verb_block(v):
    usage, about = split_usage(v["usage"])
    lines = ["#### `%s`" % v["verb"], ""]
    if about:
        lines += [about[0].upper() + about[1:] + ("" if about.endswith(".") else "."), ""]
    lines += ["```", usage, "```", ""]
    fl = flags(usage)
    if fl:
        lines += ["Flags: " + ", ".join("`%s`" % f for f in fl) + ".", ""]
    if v["mutates"]:
        lines += ["It changes things, so it runs only through the running app, unless `--dry-run` is given.", ""]
    return lines


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: clidoc.py <MinMacs binary> [repo root]")
    binary = os.path.abspath(sys.argv[1])
    root = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    with tempfile.TemporaryDirectory(prefix="mmclidoc.") as home:
        os.makedirs(os.path.join(home, "bin"))
        helps = {p: help_of(binary, p, home) for p in PROGRAMS}

    out = ["# CLI", "",
           "This page is generated from `minmacs help --json` by `test/docs/clidoc.py`. `./test.sh docs` fails when it does not match the built binary. "
           "To write it again after a verb changes:", "",
           "```sh",
           "python3 -I test/docs/clidoc.py build/MinMacs.app/Contents/MacOS/MinMacs > docs/CLI.md",
           "```", "",
           "The app binary is also the command line tool. `install.sh` and `build.sh --install` link it as `~/.local/bin/minmacs`. "
           "When the app runs, the CLI hands each verb to it over `core.sock` in the support folder. When no app answers, it builds a snapshot itself and answers from that.", "",
           "## Exit codes", ""]
    for num, name, note in exit_codes(root):
        out.append("- **%d.** %s" % (num, (note[0].upper() + note[1:] + ".") if note else name[len("MMExit"):] + "."))
    out += ["", "## minmacs", ""]
    sections = []
    for v in helps["minmacs"]["verbs"]:
        if v["section"] not in sections:
            sections.append(v["section"])
    for s in sections:
        out += ["### %s" % s, ""]
        for v in helps["minmacs"]["verbs"]:
            if v["section"] == s:
                out += verb_block(v)

    out += ["## The old names", "",
            "The binary looks at the name it was started under. A link named `locohost`, `workforest`, `noo-noo` or `insomnia` "
            "answers that expert's verbs first, then the verbs of `minmacs`. Below is what differs from `minmacs` under each name.", ""]
    base = {(v["verb"], v["usage"]) for v in helps["minmacs"]["verbs"]}
    base_verbs = [v["verb"] for v in helps["minmacs"]["verbs"]]
    own_names = {"minmacs": set(base_verbs)}
    for p in PROGRAMS[1:]:
        verbs = helps[p]["verbs"]
        own = [v for v in verbs if (v["verb"], v["usage"]) not in base]
        names = {v["verb"] for v in verbs}
        gone = [b for b in base_verbs if b not in names]
        section = SECTIONS[p]
        own_names[p] = {v["verb"] for v in own} | {v["verb"] for v in verbs if v["section"] == section}
        out += ["### %s" % p, ""]
        if gone:
            out += ["Not under this name: " + ", ".join("`%s`" % g for g in gone) + ".", ""]
        if not own:
            out += ["Every verb is the same as under `minmacs`.", ""]
        for v in own:
            out += verb_block(v)

    table = aliases(root)
    out += ["### Commands of the 1.x apps", "",
            "An old command that is no verb under that name is rewritten to 2.0 words before it runs. "
            "Under an old name, the expert's own verb wins over the rewrite. Under `minmacs`, any 2.0 verb wins. "
            "`<arg>` is the old command's first argument. The rewrites are read from `MMLegacyWords` in `Sources/CLI/MMCLI.m`, "
            "and only the ones that apply are listed.", ""]
    for p in ["minmacs", "locohost", "workforest"]:
        rows = [(old, new) for old, new in table[p] if old not in own_names[p]]
        out += ["Under `%s`:" % p, ""]
        if not rows:
            out += ["None apply. Every old command is a verb of its own under this name.", ""]
            continue
        for old, new in rows:
            out.append("- `%s %s` becomes `%s %s`." % (p, old, p, new))
        out.append("")
    while out and out[-1] == "":
        out.pop()
    print("\n".join(out))


main()
