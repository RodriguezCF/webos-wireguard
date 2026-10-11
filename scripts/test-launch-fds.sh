#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LAUNCHER="${1:-$ROOT/app/com.github.cfernande1470.wireguard/payload/wireguard/scripts/exec-clean.sh}"
LAUNCH_SHELL="${FD_TEST_SHELL:-/bin/sh}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

printf '%s\n' 'stdin-preserved' > "$WORK/input"
exec 9> "$WORK/inherited"
eval 'exec 23> "$WORK/inherited-high"'
FD_TEST_VALUE=env-preserved "$LAUNCH_SHELL" "$LAUNCHER" /bin/sh -c '
  for fd in 9 10 23; do
    [ ! -e "/proc/$$/fd/$fd" ] || exit 10
  done
  read -r line
  [ "$line" = stdin-preserved ] || exit 11
  [ "$FD_TEST_VALUE" = env-preserved ] || exit 12
  printf "%s\n" "$$" > "$1"
  printf "%s\n" stdout-preserved
  printf "%s\n" stderr-preserved >&2
' fd-test "$WORK/pid" < "$WORK/input" > "$WORK/output" 2> "$WORK/error" &
pid=$!
wait "$pid" || { cat "$WORK/error" >&2; exit 1; }
[ "$(cat "$WORK/pid")" = "$pid" ]
grep -qx stdout-preserved "$WORK/output"
grep -qx stderr-preserved "$WORK/error"
[ -e "/proc/$$/fd/9" ]
[ -e "/proc/$$/fd/23" ]
exec 9>&-
eval 'exec 23>&-'
echo "Clean launch passed: inherited descriptors closed; PID, stdio and environment preserved"
