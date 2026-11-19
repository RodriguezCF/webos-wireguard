#!/bin/sh
set -eu

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/lib.sh"

mkdir -p "$RUN"

acquire_operation_lock
trap 'rc=$?; release_lock_dir; exit "$rc"' EXIT
trap 'exit 1' HUP INT TERM

echo "== stopping watchdog =="
stop_watchdog

# Full teardown: routes, endpoint routes, IPv6 block routes, interface,
# wireguard-go, DNS redirection, IPv6 settings and the kill switch chain.
teardown_tunnel 0

write_state stopped ""
echo "OK: WireGuard stopped"
