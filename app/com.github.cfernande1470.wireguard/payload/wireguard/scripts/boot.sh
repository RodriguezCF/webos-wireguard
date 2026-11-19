#!/bin/sh
set -eu

BASE="/var/lib/webosbrew/wireguard"
INIT_FILE="/var/lib/webosbrew/init.d/90-wireguard"
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
HERE="$(CDPATH= cd -- "$(dirname -- "$SELF")" && pwd)"

cleanup_stale_state() {
  echo "WireGuard payload is missing; removing stale runtime and private configuration"
  killall wireguard-go 2>/dev/null || true
  killall wg-upload 2>/dev/null || true
  ip link del wg0 2>/dev/null || true
  rm -f /var/run/wireguard/wg0.sock
  rm -f "$INIT_FILE"
  rm -rf "$BASE"
}

if [ ! -x "$HERE/start.sh" ] || [ ! -f "$HERE/lib.sh" ] || [ ! -x "$HERE/../bin/wg" ] || [ ! -x "$HERE/../bin/wireguard-go" ]; then
  cleanup_stale_state
  exit 0
fi

. "$HERE/lib.sh"

mkdir -p "$RUN"

ATTEMPTS=5

write_boot_result() {
  {
    echo "result=$1"
    echo "attempts=$2"
    echo "time=$(now_s)"
  } > "$BOOT_RESULT_FILE.tmp" && mv -f "$BOOT_RESULT_FILE.tmp" "$BOOT_RESULT_FILE"
}

has_default_route() {
  ip route show default 2>/dev/null | grep -q default
}

(
  set +e
  echo "autostart: $(date)"

  if ks_enabled; then
    # Endpoint lookups need the network, so wait for it before blocking.
    i=0
    while [ "$i" -lt 60 ] && ! has_default_route; do
      sleep 1
      i=$((i + 1))
    done
    echo "kill switch on: blocking traffic outside the tunnel until it is up"
    ks_boot_prepare
    if ipt4_usable; then
      ks_apply boot || echo "WARNING: kill switch firewall rules could not be added; routes still block"
    else
      echo "kill switch mode: routes only (no usable iptables)"
    fi
    write_state blocked "autostart: waiting for the tunnel"
  fi

  attempt=1
  delay=10
  while [ "$attempt" -le "$ATTEMPTS" ]; do
    # Some TVs restore networking late after a cold boot. Wait up to 60 seconds.
    i=0
    while [ "$i" -lt 60 ] && ! has_default_route; do
      sleep 1
      i=$((i + 1))
    done

    if ! has_default_route; then
      echo "attempt $attempt of $ATTEMPTS: no default route after 60 seconds"
    else
      echo "== attempt $attempt of $ATTEMPTS =="
      if WG_KEEP_KILLSWITCH=1 "$HERE/start.sh"; then
        write_boot_result ok "$attempt"
        echo "autostart: connected on attempt $attempt"
        exit 0
      fi
    fi

    if [ "$attempt" -lt "$ATTEMPTS" ]; then
      echo "retrying in $delay seconds"
      sleep "$delay"
      delay=$((delay * 2))
    fi
    attempt=$((attempt + 1))
  done

  write_boot_result failed "$ATTEMPTS"
  if ks_enabled; then
    write_state blocked "autostart failed; kill switch keeps traffic blocked"
  else
    write_state failed "autostart failed"
  fi
  echo "ERROR: autostart failed after $ATTEMPTS attempts"
  exit 1
) >"$RUN/autostart.log" 2>&1 &

exit 0
