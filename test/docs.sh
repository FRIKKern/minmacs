# ===== Docs: the pages for 2.0 match the code, issue #38 =====
# Sourced by test.sh after core. Starts no process but the binary's help, the render tool and python, and
# writes only inside $MINMACS_HOME. Nothing here opens the app.
dc_dir="$MINMACS_HOME/docs.$$"
mkdir -p "$dc_dir"

# docs/CLI.md is generated from help --json under each program name, so it cannot drift from the verb registry.
python3 -I test/docs/clidoc.py "$BIN" "$ROOT" >"$dc_dir/CLI.md" 2>"$dc_dir/clidoc.err"
check "docs: clidoc.py writes the CLI page" 0 "$?"
check "docs: docs/CLI.md matches help --json of the built binary" same "$(cmp -s "$dc_dir/CLI.md" docs/CLI.md && echo same || echo differs)"
cmp -s "$dc_dir/CLI.md" docs/CLI.md || { diff docs/CLI.md "$dc_dir/CLI.md" | head -20; echo "  write it again: python3 -I test/docs/clidoc.py <binary> > docs/CLI.md"; }
dc_verbs=$("$BIN" help --json 2>/dev/null | json "' '.join(v['verb'] for v in j['verbs'])")
dc_missing=""
for v in $dc_verbs; do grep -q "^#### \`$v\`" docs/CLI.md || dc_missing="$dc_missing $v"; done
check "docs: CLI.md has a heading for every verb of minmacs" "" "$dc_missing"

# docs/PRIVACY.md lists every key each reviewRequest sends, and no key it does not.
python3 -I test/docs/privacy.py "$ROOT" >"$dc_dir/privacy.txt" 2>&1
check "docs: privacy.py passes" 0 "$?"
grep '^FAIL' "$dc_dir/privacy.txt" | sed 's/^/  /'
check "docs: privacy.py ran every check" 36 "$(grep -c '^ok' "$dc_dir/privacy.txt")"
# The check fails when an expert starts to send a key the page does not list.
dc_fx="$dc_dir/privacy-fx"
mkdir -p "$dc_fx/docs" "$dc_fx/Sources/Core/Review" "$dc_fx/Sources/Experts"
cp docs/PRIVACY.md "$dc_fx/docs/" && cp Sources/Core/Review/MMReview.m "$dc_fx/Sources/Core/Review/" && cp -R Sources/Experts/. "$dc_fx/Sources/Experts/"
python3 -I - "$dc_fx/Sources/Experts/LocoHost/MMLocoHost.m" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('    x[@"ports"] = h.ports', '    x[@"probe_key"] = @1;\n    x[@"ports"] = h.ports', 1)
open(p, "w").write(s)
EOF
python3 -I test/docs/privacy.py "$dc_fx" >"$dc_dir/privacy-fx.txt" 2>&1
check "docs: privacy.py fails on a key PRIVACY.md does not list" 1 "$?"
check "docs: privacy.py names that key" 1 "$(grep -c 'LocoHost sends: not listed: probe_key' "$dc_dir/privacy-fx.txt")"
# It fails too when an expert merges a dictionary into its facts, since the reader cannot name those keys.
cp Sources/Experts/LocoHost/MMLocoHost.m "$dc_fx/Sources/Experts/LocoHost/"
python3 -I - "$dc_fx/Sources/Experts/WorkForest/MMWorkForest.m" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('    x[@"repo"] = t.repoName;', '    [x addEntriesFromDictionary:f.facts];\n    x[@"repo"] = t.repoName;', 1)
open(p, "w").write(s)
EOF
python3 -I test/docs/privacy.py "$dc_fx" >"$dc_dir/privacy-fx2.txt" 2>&1
check "docs: privacy.py fails on a merged dictionary" 1 "$?"
check "docs: privacy.py names the merge" 1 "$(grep -c 'WorkForest: every key in .* found addEntriesFromDictionary' "$dc_dir/privacy-fx2.txt")"

# The README's pictures are renders of tools/render.sh.
dc_missing=""
for f in $(grep -o 'docs/img/[a-z0-9-]*\.png' README.md | sort -u); do [ -f "$f" ] || dc_missing="$dc_missing $f"; done
check "docs: every picture README.md names is in docs/img" "" "$dc_missing"
dc_unused=""
for f in docs/img/*.png; do grep -q "$f" README.md || dc_unused="$dc_unused $f"; done
check "docs: README.md shows every picture in docs/img" "" "$dc_unused"
BUILD_DIR="$dc_dir/render-build" tools/render.sh "$dc_dir/render" >"$dc_dir/render.log" 2>&1
check "docs: tools/render.sh renders" 0 "$?"
dc_missing=""; dc_diff=""
for f in docs/img/*.png; do
  b=$(basename "$f")
  if [ ! -f "$dc_dir/render/$b" ]; then dc_missing="$dc_missing $b"
  elif ! cmp -s "$f" "$dc_dir/render/$b"; then dc_diff="$dc_diff $b"; fi
done
check "docs: every picture in docs/img is one the render tool writes" "" "$dc_missing"
# A menu change in another expert changes its render, so a difference is reported, not failed.
[ -z "$dc_diff" ] || printf '  info  %s\n' "docs/img differs from this render:$dc_diff. Copy them from tools/render.sh's output after a look."

# Plain writing in the pages this section owns: no em dashes, no home folder of a real person.
dc_pages="README.md AGENTS.md docs/HOW-IT-WORKS.md docs/REVIEW.md docs/CLI.md docs/PRIVACY.md docs/DESIGN.md"
check "docs: no em dash in the 2.0 pages" 0 "$(cat $dc_pages | grep -c '—')"
check "docs: no /Users/ path in the 2.0 pages" 0 "$(cat $dc_pages | grep -c '/Users/')"
# Every relative link in those pages leads to a file.
dc_broken=$(python3 -I - $dc_pages <<'EOF'
import os, re, sys
bad = []
for page in sys.argv[1:]:
    text = open(page).read()
    for target in re.findall(r"\]\(([^)\s]+)\)", text) + re.findall(r'(?:src|srcset)="([^"]+)"', text):
        if re.match(r"^[a-z]+:", target) or target.startswith("#"):
            continue
        path = os.path.normpath(os.path.join(os.path.dirname(page), target.split("#")[0]))
        if not os.path.exists(path):
            bad.append("%s:%s" % (page, target))
print(" ".join(bad))
EOF
)
check "docs: every relative link in the 2.0 pages leads to a file" "" "$dc_broken"
