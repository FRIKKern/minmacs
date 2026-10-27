#!/bin/sh
# What does /usr/libexec/tmp_cleaner remove, and who creates the large $TMPDIR families? Read-only.
# Part 1 prints the launchd job and the script itself. It is a 35-line shell script.
# Part 2 counts files in /private/tmp by which of the three times are older than 3 days.
#   If the cleaner runs every night, no file has all three older than 4 days.
# Part 3 groups $TMPDIR by family, the name with its random suffix cut off.
set -u
echo "== launchd job"
plutil -p /System/Library/LaunchDaemons/com.apple.tmp_cleaner.plist
echo "== the script"
cat /usr/libexec/tmp_cleaner
echo "== /private/tmp at $(date -u +%FT%TZ)"
cd /private/tmp || exit 1
echo "files:                         $(find -x . -type f 2>/dev/null | wc -l)"
echo "all of atime mtime ctime > 3d: $(find -x . -type f -atime +3 -mtime +3 -ctime +3 2>/dev/null | wc -l)"
echo "all three > 4d:                $(find -x . -type f -atime +4 -mtime +4 -ctime +4 2>/dev/null | wc -l)"
echo "mtime > 3d, atime newer:       $(find -x . -type f -mtime +3 ! -atime +3 2>/dev/null | wc -l)"
echo "mtime, atime > 3d, ctime newer: $(find -x . -type f -mtime +3 -atime +3 ! -ctime +3 2>/dev/null | wc -l)"
echo "oldest mtime of a survivor:    $(find -x . -type f -mtime +3 -exec stat -f '%Sm' -t '%F' {} + 2>/dev/null | sort | head -1)"
echo "survivors with an old mtime, by top folder:"
find -x . -type f -mtime +3 2>/dev/null | awk -F/ '{print $2}' | sort | uniq -c | sort -rn | head -8
echo "== dirhelper job, which cleans \$TMPDIR"
plutil -p /System/Library/LaunchDaemons/com.apple.bsd.dirhelper.plist 2>/dev/null
echo "== \$TMPDIR families: count, oldest and newest folder date, KB"
cd "${TMPDIR:?}" || exit 1
ls | sed -E 's/[-_.]?[0-9A-Za-z]{6,}$//' | sort | uniq -c | sort -rn | head -14 | while read -r n f; do
  o=$(ls -dtr "$f"* 2>/dev/null | head -1); w=$(ls -dt "$f"* 2>/dev/null | head -1)
  printf '%6s %-24s %s %s %sKB\n' "$n" "$f" "$(stat -f %Sm -t %F "$o")" "$(stat -f %Sm -t %F "$w")" "$(du -skc "$f"* 2>/dev/null | tail -1 | cut -f1)"
done
