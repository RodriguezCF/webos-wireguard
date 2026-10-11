#!/bin/sh
set -eu

# A Homebrew exec request can pass Luna sockets and other native descriptors
# through its shell. A daemon must not keep those service connections alive.
exec_clean() {
  # Keep the loop and exec in a parsed function: the shell may also close the
  # descriptor from which it was reading this script. /proc/self refers to this
  # process, whereas $$ can refer to a parent when called inside a subshell.
  for fd in /proc/self/fd/*; do
    n=${fd##*/}
    case "$n" in
      ''|*[!0-9]*) continue ;;
    esac
    if [ "$n" -gt 2 ] && [ -L "$fd" ]; then
      eval "exec $n>&-"
    fi
  done
  exec "$@"
}

[ "$#" -gt 0 ] || { echo "ERROR: missing command" >&2; exit 1; }
exec_clean "$@"
