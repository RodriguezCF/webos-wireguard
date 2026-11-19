#!/bin/sh
set -eu

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/lib.sh"

mkdir -p "$BASE/conf" "$RUN"

case "${1:-status}" in
  enable)
    echo "killswitch=1" > "$KILLSWITCH_CONF"
    chmod 600 "$KILLSWITCH_CONF"
    if tunnel_running; then
      ks_routes_apply || echo "WARNING: kill switch routes could not be added"
      if ipt4_usable && ks_apply strict; then
        echo "Kill switch: on (firewall and routes)"
      fi
    fi
    if ! ipt4_usable; then
      echo "Kill switch mode: routes only (this kernel has no usable iptables)"
    fi
    echo "Kill switch: enabled"
    echo "KILLSWITCH=1"
    ;;

  disable)
    echo "killswitch=0" > "$KILLSWITCH_CONF"
    chmod 600 "$KILLSWITCH_CONF"
    ks_remove
    ks_routes_remove
    echo "Kill switch: disabled"
    echo "KILLSWITCH=0"
    ;;

  status)
    if ks_enabled; then
      echo "Kill switch: enabled ($(ks_status_word))"
      echo "KILLSWITCH=1"
    else
      echo "Kill switch: disabled"
      echo "KILLSWITCH=0"
    fi
    ;;

  *)
    echo "Usage: $0 enable|disable|status"
    exit 2
    ;;
esac
