# The Core headers compile, issue #11. Sourced by test.sh, which defines check, ROOT and MINMACS_HOME.
# Every check compiles only. Nothing is linked or run, and nothing outside $MINMACS_HOME is written.

H="$MINMACS_HOME/headers"
mkdir -p "$H"
# The flags of build.sh, plus stricter warnings, and any warning fails.
CC="clang -fobjc-arc -mmacosx-version-min=14.0 -arch arm64 -arch x86_64 -ISources -Wall -Wextra -Wno-unused-parameter -Wstrict-prototypes -Werror"
headers=$(find Sources/Core -name '*.h' | LC_ALL=C sort)

missing=0
for h in $headers; do
  grep -q "^#import \"${h#Sources/}\"" test/headers/check.m || { missing=$((missing+1)); echo "    check.m does not import $h"; }
done
check "check.m imports every Core header" 0 "$missing"

$CC -c test/headers/check.m -o "$H/check.o" >"$H/check.log" 2>&1
r=$?; [ "$r" = 0 ] || tail -20 "$H/check.log"
check "every Core header compiles with no warnings" 0 "$r"

$CC -DMM_TESTS -c test/headers/check.m -o "$H/check-tests.o" >"$H/check-tests.log" 2>&1
r=$?; [ "$r" = 0 ] || tail -20 "$H/check-tests.log"
check "the headers compile with MM_TESTS too" 0 "$r"

# A header that needs another to be imported first fails here.
alone=0
for h in $headers; do
  f="$H/alone-$(basename "$h" .h).m"
  printf '#import "%s"\n' "${h#Sources/}" >"$f"
  $CC -c "$f" -o "${f%.m}.o" >"${f%.m}.log" 2>&1 || { alone=$((alone+1)); echo "    $h does not compile alone"; tail -5 "${f%.m}.log"; }
done
check "each Core header compiles on its own" 0 "$alone"

appkit=$(grep -lE '^#import <(Cocoa|AppKit)/' $headers | grep -c .)
check "no Core header imports AppKit" 0 "$appkit"

# Core shares one compile with the kit and the CLI, so a name both declare fails here.
# The headers in Sources/UI import Cocoa, which is fine outside Core. -fsyntax-only, because only the names matter.
f="$H/together.m"
printf '#import "Core/MMCore.h"\n' >"$f"
for h in $(find Sources/UI Sources/CLI -name '*.h' 2>/dev/null | LC_ALL=C sort); do printf '#import "%s"\n' "${h#Sources/}" >>"$f"; done
# MMRowMark must follow the kit's MMMark member for member, so the kit can cast it.
if [ -f Sources/UI/MMMenuKit.h ]; then
  for m in None Working Recent Quiet Goes Blocked Unknown; do
    printf '_Static_assert((NSInteger)MMRowMark%s == (NSInteger)MMMark%s, "MMRowMark%s");\n' $m $m $m >>"$f"
  done
fi
$CC -fsyntax-only "$f" >"$H/together.log" 2>&1
r=$?; [ "$r" = 0 ] || tail -10 "$H/together.log"
check "Core shares no name with Sources/UI or Sources/CLI" 0 "$r"

unnamed=0
for n in $(seq 1 66); do
  grep -rqw "P$n" Sources/Core --include='*.h' || { unnamed=$((unnamed+1)); echo "    no Core header names P$n"; }
done
check "the headers name every pattern P1 to P66" 0 "$unnamed"

bad=$(python3 test/headers/prefix.py $headers)
[ -z "$bad" ] || printf '%s\n' "$bad" | sed 's/^/    /'
check "every Core symbol starts with MM" 0 "$(printf '%s' "$bad" | grep -c .)"
