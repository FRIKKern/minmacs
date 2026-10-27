#!/bin/sh
# Stands in for sudo, pmset and osascript in the Insomnia checks. MMLidOverride runs it in place of the real
# program, with the real command line as its arguments. It logs each call and keeps the lid state in a file
# under $MINMACS_HOME/insomnia-fake, which the test's fake power source reads. Nothing real is run.
d="$MINMACS_HOME/insomnia-fake"
mkdir -p "$d"
printf '%s\n' "$*" >>"$d/log"
case "$*" in
  "/usr/bin/sudo -n -l /usr/bin/pmset -a disablesleep 1")
    [ -f "$d/rule" ] && exit 0
    echo "sudo: a password is required" >&2; exit 1 ;;
  "/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 1"|"/usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0")
    [ -f "$d/fail" ] && { echo "sudo: a password is required" >&2; exit 1; }
    [ -f "$d/rule" ] || { echo "sudo: a password is required" >&2; exit 1; }
    echo "${6}" >"$d/lid"
    echo "${6}" >>"$d/done" ;;
  "/usr/bin/pmset displaysleepnow") ;;
  "/usr/bin/osascript -e "*)
    # The rule Insomnia writes, word for word, and nothing else.
    case "$3" in
      *"ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0' > /etc/sudoers.d/insomnia && chmod 0440 /etc/sudoers.d/insomnia && visudo -cf /etc/sudoers.d/insomnia"*"with administrator privileges")
        [ -f "$d/deny" ] && { echo "User canceled." >&2; exit 1; }
        touch "$d/rule" ;;
      *) echo "unexpected script" >&2; exit 2 ;;
    esac ;;
  *) echo "unexpected command: $*" >&2; exit 2 ;;
esac
