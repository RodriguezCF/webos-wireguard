#!/bin/sh
# Shared settings and helpers for the WireGuard scripts.
#
# Sourced (not executed) by start.sh, stop.sh, watchdog.sh, boot.sh,
# killswitch.sh, summary.sh, leaktest.sh, status.sh and uninstall.sh after
# they set HERE. Busybox ash compatible: no bash-isms and no "local", so
# helper variables carry a short per-function prefix instead.

BASE="/var/lib/webosbrew/wireguard"
IFACE="wg0"
WG="$HERE/../bin/wg"
WGGO="$HERE/../bin/wireguard-go"
INIT_FILE="/var/lib/webosbrew/init.d/90-wireguard"

CONF="$BASE/conf/wg0.conf"
ADDRESS_FILE="$BASE/conf/address"
ROUTES_EXTRA_FILE="$BASE/conf/routes-extra"
DNS_CONF_FILE="$BASE/conf/dns"
KILLSWITCH_CONF="$BASE/conf/killswitch"

RUN="$BASE/run"
PIDFILE="$RUN/wireguard-go.pid"
LOGFILE="$RUN/wireguard-go.log"
GWFILE="$RUN/original-gateway"
DEVFILE="$RUN/original-dev"
GW6FILE="$RUN/original-gateway6"
DEV6FILE="$RUN/original-dev6"
ENDPOINTS_FILE="$RUN/endpoint-routes"
APPLIED_ROUTES_FILE="$RUN/applied-routes"
SETCONF_FILE="$RUN/wg0.setconf"
LEGACY_IPV6_STATE_FILE="$RUN/original-ipv6-disabled"
IPV6_SAVED_FILE="$RUN/ipv6-saved"
IPV6_KEEP_FILE="$RUN/ipv6-keep"
V6BLOCK_FILE="$RUN/ipv6-block-routes"
KS_ROUTES_FILE="$RUN/killswitch-routes"
ENDPOINT_CACHE="$RUN/endpoint-cache"
PROBE_ROUTE_FILE="$RUN/probe-route"
DNS_SERVERS_FILE="$RUN/dns-servers"
DNS_SEARCH_FILE="$RUN/dns-search"
DNS_RESOLV="$RUN/resolv.conf.wg"
DNS_ORIG="$RUN/resolv.conf.orig"
DNS_TARGET_FILE="$RUN/dns-target"
DNS_MODE_FILE="$RUN/dns-mode"
DNS_BASEMOUNTS_FILE="$RUN/dns-base-mounts"
DNS_ROUTES_FILE="$RUN/dns-routes"
DNS_MARKER="# webos-wireguard: tunnel DNS"
KS_CHAIN="WG_KILLSWITCH"
KS_STATE_FILE="$RUN/killswitch-active"
KS_SIG_FILE="$RUN/killswitch-signature"
STATE_FILE="$RUN/state"
WATCHDOG_PIDFILE="$RUN/watchdog.pid"
WATCHDOG_LOG="$RUN/watchdog.log"
BOOT_RESULT_FILE="$RUN/boot-result"
OPERATION_LOCK="$RUN/operation.lock"

# ---------------------------------------------------------------- basics

now_s() {
  date +%s
}

is_ipv4() {
  case "$1" in
    ""|*[!0-9.]*) return 1 ;;
    *.*.*.*) return 0 ;;
  esac
  return 1
}

is_ipv6() {
  case "$1" in
    *:*)
      case "$1" in
        *[!0-9A-Fa-f:.]*) return 1 ;;
      esac
      return 0
      ;;
  esac
  return 1
}

read_kv() {
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1
}

write_state() {
  ws_tmp="$STATE_FILE.tmp"
  {
    echo "state=$1"
    echo "since=$(now_s)"
    echo "detail=${2:-}"
  } > "$ws_tmp" 2>/dev/null && mv -f "$ws_tmp" "$STATE_FILE" 2>/dev/null
  return 0
}

tunnel_running() {
  [ -f "$PIDFILE" ] &&
    kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null &&
    ip link show "$IFACE" >/dev/null 2>&1
}

# ---------------------------------------------------------------- locking

acquire_operation_lock() {
  if mkdir "$OPERATION_LOCK" 2>/dev/null; then
    echo "$$" > "$OPERATION_LOCK/pid"
    return 0
  fi

  lock_pid="$(cat "$OPERATION_LOCK/pid" 2>/dev/null || true)"
  if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
    echo "ERROR: another WireGuard start/stop operation is running (PID $lock_pid)"
    exit 1
  fi

  rm -rf "$OPERATION_LOCK"
  mkdir "$OPERATION_LOCK"
  echo "$$" > "$OPERATION_LOCK/pid"
}

release_lock_dir() {
  rm -rf "$OPERATION_LOCK"
}

# True while another live process runs start.sh or stop.sh.
operation_busy() {
  [ -d "$OPERATION_LOCK" ] || return 1
  ob_pid="$(cat "$OPERATION_LOCK/pid" 2>/dev/null || true)"
  [ -n "$ob_pid" ] && [ "$ob_pid" != "$$" ] && kill -0 "$ob_pid" 2>/dev/null
}

# ---------------------------------------------------------------- watchdog

stop_watchdog() {
  sw_pid="$(cat "$WATCHDOG_PIDFILE" 2>/dev/null || true)"
  rm -f "$WATCHDOG_PIDFILE"
  if [ -n "$sw_pid" ] && [ "$sw_pid" != "$$" ]; then
    kill "$sw_pid" 2>/dev/null || true
    # Let a repair step that was already running finish before tearing down.
    sw_i=0
    while [ "$sw_i" -lt 10 ] && kill -0 "$sw_pid" 2>/dev/null; do
      sleep 0.3 2>/dev/null || sleep 1
      sw_i=$((sw_i + 1))
    done
  fi
  # A watchdog that missed the signal exits on its own at its next round,
  # because it only keeps running while the PID file names it.
  return 0
}

# ---------------------------------------------------------------- config parsing

# Prints the comma separated values of an [Interface] key, one per line.
conf_interface_values() {
  [ -f "$1" ] || return 0
  awk -v want="$2" '
    { sub(/\r$/, ""); sub(/[ \t]*#.*$/, "") }
    /^[ \t]*\[/ { s = tolower($0); gsub(/[ \t]/, "", s); next }
    s == "[interface]" && index($0, "=") > 0 {
      k = substr($0, 1, index($0, "=") - 1)
      gsub(/[ \t]/, "", k)
      if (tolower(k) != want) next
      v = substr($0, index($0, "=") + 1)
      n = split(v, parts, ",")
      for (i = 1; i <= n; i++) {
        p = parts[i]
        gsub(/^[ \t]+|[ \t]+$/, "", p)
        if (p != "") print p
      }
    }' "$1"
}

# Prints "public-key endpoint" for every [Peer] with an Endpoint.
peer_endpoints_from_conf() {
  [ -f "$CONF" ] || return 0
  awk '
    function flush() { if (pk != "" && ep != "") print pk, ep; pk = ""; ep = "" }
    { sub(/\r$/, ""); sub(/[ \t]*#.*$/, "") }
    /^[ \t]*\[/ { flush(); s = tolower($0); gsub(/[ \t]/, "", s); next }
    s == "[peer]" && index($0, "=") > 0 {
      k = substr($0, 1, index($0, "=") - 1)
      gsub(/[ \t]/, "", k)
      k = tolower(k)
      v = substr($0, index($0, "=") + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (k == "publickey") pk = v
      else if (k == "endpoint") ep = v
    }
    END { flush() }' "$CONF"
}

endpoint_host() {
  case "$1" in
    \[*\]:*)
      eh="${1#\[}"
      echo "${eh%%\]*}"
      ;;
    *)
      echo "${1%:*}"
      ;;
  esac
}

endpoint_port() {
  echo "${1##*:}"
}

# ---------------------------------------------------------------- default routes

detect_default4() {
  dd_line="$(ip route show default 2>/dev/null | grep -v " dev $IFACE" | head -1 || true)"
  D4_GW="$(echo "$dd_line" | sed -n 's/.*default via \([^ ]*\).*/\1/p')"
  D4_DEV="$(echo "$dd_line" | sed -n 's/.* dev \([^ ]*\).*/\1/p')"
}

detect_default6() {
  dd_line="$(ip -6 route show default 2>/dev/null | grep -v " dev $IFACE" | head -1 || true)"
  D6_GW="$(echo "$dd_line" | sed -n 's/.*default via \([^ ]*\).*/\1/p')"
  D6_DEV="$(echo "$dd_line" | sed -n 's/.* dev \([^ ]*\).*/\1/p')"
}

# ---------------------------------------------------------------- endpoints

# Prints "family host port" for every peer endpoint WireGuard currently uses.
endpoints_list() {
  [ -x "$WG" ] || return 0
  "$WG" show "$IFACE" endpoints 2>/dev/null | while read -r el_peer el_ep; do
    [ -n "$el_peer" ] || continue
    case "$el_ep" in
      ""|"(none)") continue ;;
    esac
    el_port="${el_ep##*:}"
    case "$el_ep" in
      \[*\]:*)
        el_host="${el_ep#\[}"
        el_host="${el_host%%\]*}"
        el_host="${el_host%%%*}"
        el_fam=6
        ;;
      *)
        el_host="${el_ep%:*}"
        el_fam=4
        ;;
    esac
    case "$el_host" in
      ""|0.0.0.0|::) continue ;;
    esac
    echo "$el_fam $el_host $el_port"
  done
}

route_del_pin() {
  if [ "$1" = 6 ]; then
    ip -6 route del "$2/128" 2>/dev/null || true
  else
    ip route del "$2" 2>/dev/null || true
  fi
}

# Routes every endpoint through the current physical default route so the
# encrypted packets never loop back into wg0. Returns 1 when a pin failed.
pin_endpoints() {
  detect_default4
  detect_default6
  pe_new="$ENDPOINTS_FILE.new"
  pe_rc=0
  : > "$pe_new"
  endpoints_list > "$RUN/endpoints.now"

  while read -r pe_fam pe_host pe_port; do
    [ -n "$pe_host" ] || continue
    if [ "$pe_fam" = 6 ]; then
      if [ -z "$D6_DEV" ]; then
        echo "WARNING: no IPv6 default route outside $IFACE; cannot pin endpoint $pe_host"
        pe_rc=1
        continue
      fi
      if [ -n "$D6_GW" ]; then
        echo "endpoint $pe_host via $D6_GW dev $D6_DEV"
        ip -6 route replace "$pe_host/128" via "$D6_GW" dev "$D6_DEV" 2>/dev/null || pe_rc=1
      else
        echo "endpoint $pe_host dev $D6_DEV"
        ip -6 route replace "$pe_host/128" dev "$D6_DEV" 2>/dev/null || pe_rc=1
      fi
    else
      if [ -z "$D4_DEV" ]; then
        echo "WARNING: no IPv4 default route outside $IFACE; cannot pin endpoint $pe_host"
        pe_rc=1
        continue
      fi
      if [ -n "$D4_GW" ]; then
        echo "endpoint $pe_host via $D4_GW dev $D4_DEV"
        ip route replace "$pe_host" via "$D4_GW" dev "$D4_DEV" 2>/dev/null || pe_rc=1
      else
        echo "endpoint $pe_host dev $D4_DEV"
        ip route replace "$pe_host" dev "$D4_DEV" 2>/dev/null || pe_rc=1
      fi
    fi
    echo "$pe_fam $pe_host" >> "$pe_new"
  done < "$RUN/endpoints.now"

  if [ -f "$ENDPOINTS_FILE" ]; then
    while read -r pe_a pe_b; do
      [ -n "$pe_a" ] || continue
      if [ -z "$pe_b" ]; then
        # 1.0.x format: one IPv4 host per line.
        pe_b="$pe_a"
        pe_a=4
      fi
      grep -qxF "$pe_a $pe_b" "$pe_new" && continue
      route_del_pin "$pe_a" "$pe_b"
    done < "$ENDPOINTS_FILE"
  fi

  mv -f "$pe_new" "$ENDPOINTS_FILE"
  rm -f "$RUN/endpoints.now"
  [ -n "$D4_DEV" ] && echo "$D4_DEV" > "$DEVFILE"
  [ -n "$D4_DEV" ] && echo "$D4_GW" > "$GWFILE"
  [ -n "$D6_DEV" ] && echo "$D6_DEV" > "$DEV6FILE"
  [ -n "$D6_DEV" ] && echo "$D6_GW" > "$GW6FILE"
  return "$pe_rc"
}

# True when every endpoint is pinned and leaves through the current physical
# default route. Uses D4_* and D6_* from detect_default4/6.
endpoint_routes_ok() {
  eo_now="$(endpoints_list | awk '{ print $1 " " $2 }' | sort)"
  eo_pinned="$(sort "$ENDPOINTS_FILE" 2>/dev/null || true)"
  [ "$eo_now" = "$eo_pinned" ] || return 1
  [ -n "$eo_now" ] || return 0

  while read -r eo_fam eo_host; do
    [ -n "$eo_host" ] || continue
    if [ "$eo_fam" = 6 ]; then
      eo_dev="$D6_DEV"
      eo_gw="$D6_GW"
      eo_get="$(ip -6 route get "$eo_host" 2>/dev/null | head -1)"
    else
      eo_dev="$D4_DEV"
      eo_gw="$D4_GW"
      eo_get="$(ip route get "$eo_host" 2>/dev/null | head -1)"
    fi
    [ -n "$eo_dev" ] || return 1
    case "$eo_get" in
      *"dev $eo_dev"*) ;;
      *) return 1 ;;
    esac
    if [ -n "$eo_gw" ]; then
      case "$eo_get" in
        *"via $eo_gw "*|*"via $eo_gw") ;;
        *) return 1 ;;
      esac
    fi
  done <<EOF
$eo_pinned
EOF
  return 0
}

# ---------------------------------------------------------------- name resolution

orig_nameservers() {
  [ -f "$DNS_ORIG" ] || return 0
  sed -n 's/^[[:space:]]*nameserver[[:space:]]*\([^[:space:]]*\).*/\1/p' "$DNS_ORIG" 2>/dev/null
}

parse_nslookup() {
  awk '
    /^Name:/ { a = 1; next }
    a && /^Address/ {
      for (i = 2; i <= NF; i++) {
        f = $i
        if (f ~ /:$/) continue
        if (f ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) { if (v4 == "") v4 = f }
        else if (f ~ /^[0-9a-fA-F:]+$/ && f ~ /:/) { if (v6 == "") v6 = f }
      }
    }
    END { if (v4 != "") print v4; else if (v6 != "") print v6 }'
}

# Opens or closes a short-lived DNS exception in the kill switch so an
# endpoint hostname can be resolved through the TV's original resolver.
ks_dns_hole() {
  for kh_tool in iptables ip6tables; do
    command -v "$kh_tool" >/dev/null 2>&1 || continue
    "$kh_tool" -L "$KS_CHAIN" -n >/dev/null 2>&1 || continue
    for kh_proto in udp tcp; do
      if [ "$1" = open ]; then
        "$kh_tool" -I "$KS_CHAIN" 1 -p "$kh_proto" --dport 53 -j ACCEPT 2>/dev/null || true
      else
        "$kh_tool" -D "$KS_CHAIN" -p "$kh_proto" --dport 53 -j ACCEPT 2>/dev/null || true
      fi
    done
  done
}

# Resolves an endpoint hostname through the TV's original resolver, not the
# tunnel DNS, so it also works while the tunnel is broken. IPv4 preferred.
resolve_host() {
  command -v nslookup >/dev/null 2>&1 || return 1
  rh_servers="$(orig_nameservers || true)"
  [ -n "$rh_servers" ] || rh_servers="-"
  rh_hole=0
  if [ -f "$KS_STATE_FILE" ]; then
    ks_dns_hole open
    rh_hole=1
  fi
  rh_out=""
  for rh_s in $rh_servers; do
    if [ "$rh_s" = "-" ]; then
      rh_out="$(nslookup "$1" 2>/dev/null | parse_nslookup)"
    else
      rh_out="$(nslookup "$1" "$rh_s" 2>/dev/null | parse_nslookup)"
    fi
    [ -n "$rh_out" ] && break
  done
  [ "$rh_hole" = 1 ] && ks_dns_hole close
  [ -n "$rh_out" ] || return 1
  echo "$rh_out"
}

# Re-resolves hostname endpoints and updates WireGuard when the address moved.
reresolve_endpoints() {
  peer_endpoints_from_conf > "$RUN/peer-endpoints"
  while read -r rr_pk rr_ep; do
    [ -n "$rr_ep" ] || continue
    rr_host="$(endpoint_host "$rr_ep")"
    rr_port="$(endpoint_port "$rr_ep")"
    case "$rr_ep" in
      \[*) continue ;;
    esac
    is_ipv4 "$rr_host" && continue
    if ! rr_addr="$(resolve_host "$rr_host")"; then
      echo "could not resolve endpoint $rr_host"
      continue
    fi
    endpoint_cache_put "$rr_host" "$rr_addr"
    case "$rr_addr" in
      *:*) rr_new="[$rr_addr]:$rr_port" ;;
      *) rr_new="$rr_addr:$rr_port" ;;
    esac
    rr_cur="$("$WG" show "$IFACE" endpoints 2>/dev/null | awk -v k="$rr_pk" '$1 == k { print $2 }')"
    if [ "$rr_cur" != "$rr_new" ]; then
      if "$WG" set "$IFACE" peer "$rr_pk" endpoint "$rr_new" 2>/dev/null; then
        echo "endpoint $rr_host moved: $rr_cur -> $rr_new"
      else
        echo "could not update endpoint $rr_host to $rr_new"
      fi
    fi
  done < "$RUN/peer-endpoints"
  rm -f "$RUN/peer-endpoints"
}

# ---------------------------------------------------------------- IPv6

ipv6_saved_has() {
  awk -v n="$1" '$1 == n { f = 1 } END { exit f ? 0 : 1 }' "$IPV6_SAVED_FILE" 2>/dev/null
}

ipv6_migrate_legacy() {
  if [ -f "$LEGACY_IPV6_STATE_FILE" ] && [ -f "$DEVFILE" ]; then
    lg_dev="$(cat "$DEVFILE" 2>/dev/null || true)"
    lg_val="$(cat "$LEGACY_IPV6_STATE_FILE" 2>/dev/null || true)"
    if [ -n "$lg_dev" ] && [ -n "$lg_val" ] && ! ipv6_saved_has "$lg_dev"; then
      echo "$lg_dev $lg_val" >> "$IPV6_SAVED_FILE"
    fi
  fi
  rm -f "$LEGACY_IPV6_STATE_FILE"
}

ipv6_restore_one() {
  ro_val="$(awk -v n="$1" '$1 == n { print $2; exit }' "$IPV6_SAVED_FILE" 2>/dev/null || true)"
  case "$ro_val" in
    0|1) echo "$ro_val" > "/proc/sys/net/ipv6/conf/$1/disable_ipv6" 2>/dev/null || true ;;
  esac
  if [ -f "$IPV6_SAVED_FILE" ]; then
    awk -v n="$1" '$1 != n' "$IPV6_SAVED_FILE" > "$IPV6_SAVED_FILE.tmp" 2>/dev/null &&
      mv -f "$IPV6_SAVED_FILE.tmp" "$IPV6_SAVED_FILE"
  fi
}

# Disables IPv6 on every interface except loopback, wg0 and the optional
# interface given as $1 (needed to reach an IPv6 endpoint). The first value
# seen for each interface is saved so stop.sh can restore it exactly.
ipv6_disable_all() {
  id_keep="${1:-}"
  [ -d /proc/sys/net/ipv6/conf ] || return 0
  ipv6_migrate_legacy
  if [ -n "$id_keep" ] && ipv6_saved_has "$id_keep"; then
    ipv6_restore_one "$id_keep"
  fi
  id_changed=""
  # Saved names read once, so a round costs no extra process per interface.
  id_saved=" $(awk '{ printf "%s ", $1 }' "$IPV6_SAVED_FILE" 2>/dev/null || true) "
  for id_path in /proc/sys/net/ipv6/conf/*; do
    id_name="${id_path##*/}"
    case "$id_name" in
      lo|all|"$IFACE") continue ;;
    esac
    if [ -n "$id_keep" ]; then
      [ "$id_name" = "$id_keep" ] && continue
      [ "$id_name" = default ] && continue
    fi
    [ -f "$id_path/disable_ipv6" ] || continue
    id_cur="$(cat "$id_path/disable_ipv6" 2>/dev/null || true)"
    case "$id_cur" in
      0|1) ;;
      *) continue ;;
    esac
    case "$id_saved" in
      *" $id_name "*) ;;
      *)
        echo "$id_name $id_cur" >> "$IPV6_SAVED_FILE"
        id_saved="$id_saved$id_name "
        ;;
    esac
    if [ "$id_cur" != 1 ]; then
      if echo 1 > "$id_path/disable_ipv6" 2>/dev/null; then
        id_changed="$id_changed $id_name"
      else
        echo "WARNING: could not disable IPv6 on $id_name"
      fi
    fi
  done
  [ -z "$id_changed" ] || echo "IPv6 disabled on:$id_changed"
  return 0
}

ipv6_restore_all() {
  ipv6_migrate_legacy
  [ -f "$IPV6_SAVED_FILE" ] || return 0
  while read -r ir_name ir_val; do
    [ -n "$ir_name" ] || continue
    case "$ir_val" in
      0|1) ;;
      *) continue ;;
    esac
    if [ -f "/proc/sys/net/ipv6/conf/$ir_name/disable_ipv6" ]; then
      echo "$ir_val" > "/proc/sys/net/ipv6/conf/$ir_name/disable_ipv6" 2>/dev/null ||
        echo "WARNING: could not restore IPv6 on $ir_name"
    fi
  done < "$IPV6_SAVED_FILE"
  rm -f "$IPV6_SAVED_FILE" "$IPV6_KEEP_FILE"
  return 0
}

# With an IPv6 endpoint, IPv6 stays enabled on the physical interface; these
# unreachable routes stop every other global IPv6 destination from leaking.
v6block_apply() {
  : > "$V6BLOCK_FILE"
  for vb_p in ::/1 8000::/1; do
    if ip -6 route replace unreachable "$vb_p" 2>/dev/null; then
      echo "$vb_p" >> "$V6BLOCK_FILE"
    else
      echo "WARNING: could not add IPv6 block route $vb_p"
    fi
  done
}

v6block_remove() {
  [ -f "$V6BLOCK_FILE" ] || return 0
  while read -r vb_p; do
    [ -n "$vb_p" ] || continue
    ip -6 route del unreachable "$vb_p" 2>/dev/null || true
  done < "$V6BLOCK_FILE"
  rm -f "$V6BLOCK_FILE"
}

# Route kill switch. While the kill switch is on and the VPN is meant to be
# up, blackhole/unreachable routes sit behind the tunnel routes with a higher
# metric. The wg0 routes (metric 0) win while wg0 exists; when wg0 vanishes
# (wireguard-go died, standby) the kernel drops them and these take over at
# once. LAN subnets and the pinned endpoint routes are more specific, so the
# LAN and the handshake keep working. Each tunnel DNS server gets a /32
# blackhole too, so DNS cannot reach a tunnel DNS address through the LAN.
# This needs no netfilter, so it is the kill switch on kernels without it;
# with iptables available the firewall chain is added on top.
KS_ROUTE_METRIC=4000

ks_routes_apply() {
  : > "$KS_ROUTES_FILE.new"
  for kr_p in 0.0.0.0/1 128.0.0.0/1; do
    ip route replace blackhole "$kr_p" metric "$KS_ROUTE_METRIC" 2>/dev/null &&
      echo "4 $kr_p" >> "$KS_ROUTES_FILE.new"
  done
  if [ -f "$DNS_SERVERS_FILE" ]; then
    while IFS= read -r kr_s; do
      [ -n "$kr_s" ] || continue
      ip route replace blackhole "$kr_s/32" metric "$KS_ROUTE_METRIC" 2>/dev/null &&
        echo "4 $kr_s/32" >> "$KS_ROUTES_FILE.new"
    done < "$DNS_SERVERS_FILE"
  fi
  for kr_p in ::/1 8000::/1; do
    ip -6 route replace unreachable "$kr_p" metric "$KS_ROUTE_METRIC" 2>/dev/null &&
      echo "6 $kr_p" >> "$KS_ROUTES_FILE.new"
  done
  # Drop entries from an earlier round that are no longer wanted.
  if [ -f "$KS_ROUTES_FILE" ]; then
    while read -r kr_f kr_p; do
      [ -n "$kr_p" ] || continue
      grep -qxF "$kr_f $kr_p" "$KS_ROUTES_FILE.new" && continue
      ks_route_del "$kr_f" "$kr_p"
    done < "$KS_ROUTES_FILE"
  fi
  mv -f "$KS_ROUTES_FILE.new" "$KS_ROUTES_FILE"
  grep -q '^4 0.0.0.0/1$' "$KS_ROUTES_FILE" && grep -q '^4 128.0.0.0/1$' "$KS_ROUTES_FILE"
}

ks_route_del() {
  if [ "$1" = 6 ]; then
    ip -6 route del unreachable "$2" metric "$KS_ROUTE_METRIC" 2>/dev/null ||
      ip -6 route del "$2" metric "$KS_ROUTE_METRIC" 2>/dev/null || true
  else
    ip route del blackhole "$2" metric "$KS_ROUTE_METRIC" 2>/dev/null ||
      ip route del "$2" metric "$KS_ROUTE_METRIC" 2>/dev/null || true
  fi
}

ks_routes_remove() {
  if [ -f "$KS_ROUTES_FILE" ]; then
    while read -r kr_f kr_p; do
      [ -n "$kr_p" ] || continue
      ks_route_del "$kr_f" "$kr_p"
    done < "$KS_ROUTES_FILE"
  fi
  # Also catch routes whose list was lost.
  for kr_p in 0.0.0.0/1 128.0.0.0/1; do
    ks_route_del 4 "$kr_p"
  done
  for kr_p in ::/1 8000::/1; do
    ks_route_del 6 "$kr_p"
  done
  rm -f "$KS_ROUTES_FILE" "$KS_ROUTES_FILE.new"
  return 0
}

ks_routes_active() {
  [ -f "$KS_ROUTES_FILE" ] && grep -q '^4 0.0.0.0/1$' "$KS_ROUTES_FILE"
}

# Endpoint hostname cache, used when a lookup fails because the kill switch
# blocks the resolver's upstream server.
endpoint_cache_put() {
  { grep -v "^$1 " "$ENDPOINT_CACHE" 2>/dev/null || true; echo "$1 $2"; } > "$ENDPOINT_CACHE.tmp" &&
    mv -f "$ENDPOINT_CACHE.tmp" "$ENDPOINT_CACHE"
  chmod 600 "$ENDPOINT_CACHE" 2>/dev/null || true
}

endpoint_cache_get() {
  awk -v h="$1" '$1 == h { print $2; exit }' "$ENDPOINT_CACHE" 2>/dev/null || true
}

# Resolves a hostname through the original resolver, falling back to the
# cached address. Prints nothing when neither works.
resolve_or_cached() {
  if roc_addr="$(resolve_host "$1")" && [ -n "$roc_addr" ]; then
    endpoint_cache_put "$1" "$roc_addr"
    echo "$roc_addr"
    return 0
  fi
  roc_addr="$(endpoint_cache_get "$1")"
  [ -n "$roc_addr" ] || return 1
  echo "$roc_addr"
}

# Boot with the kill switch on: pin the configured endpoints (resolving
# hostnames first), then add the kill switch routes and point the resolver at
# the tunnel DNS, so nothing leaves outside the tunnel before it is up.
ks_boot_prepare() {
  detect_default4
  detect_default6
  : > "$ENDPOINTS_FILE.new"
  peer_endpoints_from_conf > "$RUN/peer-endpoints"
  while read -r kb_pk kb_ep; do
    [ -n "$kb_ep" ] || continue
    kb_host="$(endpoint_host "$kb_ep")"
    case "$kb_ep" in
      \[*) kb_addr="$kb_host" ;;
      *)
        if is_ipv4 "$kb_host"; then
          kb_addr="$kb_host"
        else
          kb_addr="$(resolve_or_cached "$kb_host" || true)"
        fi
        ;;
    esac
    [ -n "$kb_addr" ] || { echo "WARNING: cannot resolve endpoint $kb_host yet"; continue; }
    case "$kb_addr" in
      *:*)
        [ -n "$D6_DEV" ] || continue
        ip -6 route replace "$kb_addr/128" ${D6_GW:+via "$D6_GW"} dev "$D6_DEV" 2>/dev/null &&
          echo "6 $kb_addr" >> "$ENDPOINTS_FILE.new"
        ;;
      *)
        [ -n "$D4_DEV" ] || continue
        ip route replace "$kb_addr" ${D4_GW:+via "$D4_GW"} dev "$D4_DEV" 2>/dev/null &&
          echo "4 $kb_addr" >> "$ENDPOINTS_FILE.new"
        ;;
    esac
  done < "$RUN/peer-endpoints"
  rm -f "$RUN/peer-endpoints"
  mv -f "$ENDPOINTS_FILE.new" "$ENDPOINTS_FILE"
  [ -n "$D4_DEV" ] && echo "$D4_DEV" > "$DEVFILE" && echo "$D4_GW" > "$GWFILE"

  prepare_dns
  ks_routes_apply || echo "WARNING: kill switch routes could not be added"
  dns_apply || true
  kb_keep=""
  grep -q '^6 ' "$ENDPOINTS_FILE" 2>/dev/null && kb_keep="$D6_DEV"
  echo "$kb_keep" > "$IPV6_KEEP_FILE"
  ipv6_disable_all "$kb_keep"
  return 0
}

# ---------------------------------------------------------------- DNS

# Collects DNS entries from conf/dns (written by the uploader), from the
# DNS line of wg0.conf, or from the newest uploaded original file.
prepare_dns() {
  : > "$DNS_SERVERS_FILE"
  : > "$DNS_SEARCH_FILE"
  pd_src=""
  pd_vals=""
  if [ -f "$DNS_CONF_FILE" ]; then
    pd_src="$DNS_CONF_FILE"
    pd_vals="$(tr ',' '\n' < "$DNS_CONF_FILE" | sed 's/\r$//;s/#.*$//;s/^[[:space:]]*//;s/[[:space:]]*$//')"
  else
    pd_vals="$(conf_interface_values "$CONF" dns)"
    [ -n "$pd_vals" ] && pd_src="$CONF"
    if [ -z "$pd_vals" ]; then
      pd_latest="$(ls -t "$BASE/uploads"/* 2>/dev/null | head -1 || true)"
      if [ -n "$pd_latest" ] && [ -f "$pd_latest" ]; then
        pd_vals="$(conf_interface_values "$pd_latest" dns)"
        [ -n "$pd_vals" ] && pd_src="$pd_latest"
      fi
    fi
  fi

  for pd_v in $pd_vals; do
    if is_ipv4 "$pd_v"; then
      grep -qxF "$pd_v" "$DNS_SERVERS_FILE" || echo "$pd_v" >> "$DNS_SERVERS_FILE"
    elif is_ipv6 "$pd_v"; then
      echo "WARNING: IPv6 DNS server ignored (IPv6 is not routed through the tunnel): $pd_v"
    else
      echo "$pd_v" >> "$DNS_SEARCH_FILE"
    fi
  done

  if [ -s "$DNS_SERVERS_FILE" ]; then
    echo "DNS from $pd_src:"
    cat "$DNS_SERVERS_FILE"
  else
    echo "WARNING: no DNS server in the configuration: the TV keeps its normal resolver (DNS leaks outside the tunnel)"
  fi
}

resolv_target() {
  rt="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
  [ -n "$rt" ] || rt="/etc/resolv.conf"
  echo "$rt"
}

mount_count() {
  awk -v t="$1" '$2 == t { n++ } END { print n + 0 }' /proc/mounts 2>/dev/null || echo 0
}

# Rewrites our resolver file in place (the bind mount follows the inode).
write_dns_resolv() {
  {
    echo "$DNS_MARKER"
    while IFS= read -r wd_s; do
      [ -n "$wd_s" ] && echo "nameserver $wd_s"
    done < "$DNS_SERVERS_FILE"
    if [ -s "$DNS_SEARCH_FILE" ]; then
      echo "search $(tr '\n' ' ' < "$DNS_SEARCH_FILE")"
    fi
  } > "$DNS_RESOLV.tmp" && cat "$DNS_RESOLV.tmp" > "$DNS_RESOLV"
  rm -f "$DNS_RESOLV.tmp"
  chmod 644 "$DNS_RESOLV" 2>/dev/null || true
}

dns_routes_apply() {
  : > "$DNS_ROUTES_FILE.new"
  while IFS= read -r dr_s; do
    [ -n "$dr_s" ] || continue
    if ip route replace "$dr_s" dev "$IFACE" 2>/dev/null; then
      echo "$dr_s" >> "$DNS_ROUTES_FILE.new"
      echo "DNS $dr_s routed through $IFACE"
    else
      echo "WARNING: could not route DNS $dr_s through $IFACE"
    fi
  done < "$DNS_SERVERS_FILE"
  mv -f "$DNS_ROUTES_FILE.new" "$DNS_ROUTES_FILE"
}

# Points the TV resolver at the tunnel DNS servers. /etc is read-only on
# webOS, so the resolver file is bind-mounted over; a plain rewrite is the
# fallback when bind mounts are not possible. The original is saved first.
dns_apply() {
  [ -s "$DNS_SERVERS_FILE" ] || return 0
  da_target="$(resolv_target)"
  dns_routes_apply
  write_dns_resolv

  if [ ! -f "$DNS_MODE_FILE" ]; then
    echo "$da_target" > "$DNS_TARGET_FILE"
    cp "$da_target" "$DNS_ORIG" 2>/dev/null || : > "$DNS_ORIG"
    mount_count "$da_target" > "$DNS_BASEMOUNTS_FILE"
    echo "resolver file: $da_target"
    if [ -e "$da_target" ] && mount -o bind "$DNS_RESOLV" "$da_target" 2>/dev/null; then
      echo bind > "$DNS_MODE_FILE"
      echo "resolver redirected with a bind mount"
    elif cat "$DNS_RESOLV" > "$da_target" 2>/dev/null; then
      echo replace > "$DNS_MODE_FILE"
      echo "resolver file replaced (original saved)"
    else
      echo "WARNING: cannot redirect $da_target to the tunnel DNS"
      rm -f "$DNS_TARGET_FILE" "$DNS_ORIG" "$DNS_BASEMOUNTS_FILE"
      return 1
    fi
  fi
  dns_check
}

# Re-applies the resolver redirection and DNS routes when something (for
# example the network manager after wake-up) undid them.
dns_check() {
  [ -f "$DNS_MODE_FILE" ] || return 0
  dc_target="$(cat "$DNS_TARGET_FILE" 2>/dev/null || true)"
  dc_mode="$(cat "$DNS_MODE_FILE" 2>/dev/null || true)"
  dc_changed=0

  if [ "$dc_mode" = bind ]; then
    dc_base="$(cat "$DNS_BASEMOUNTS_FILE" 2>/dev/null || echo 0)"
    if [ "$(mount_count "$dc_target")" -le "$dc_base" ]; then
      if mount -o bind "$DNS_RESOLV" "$dc_target" 2>/dev/null; then
        dc_changed=1
      else
        echo "WARNING: lost the DNS bind mount on $dc_target"
      fi
    fi
  fi

  if ! grep -qF "$DNS_MARKER" /etc/resolv.conf 2>/dev/null; then
    if [ "$dc_mode" = replace ]; then
      cp "$dc_target" "$DNS_ORIG" 2>/dev/null || true
      cat "$DNS_RESOLV" > "$dc_target" 2>/dev/null || true
    else
      write_dns_resolv
    fi
    dc_changed=1
  fi

  if [ -f "$DNS_ROUTES_FILE" ] && ip link show "$IFACE" >/dev/null 2>&1; then
    while IFS= read -r dc_s; do
      [ -n "$dc_s" ] || continue
      case "$(ip route get "$dc_s" 2>/dev/null | head -1)" in
        *"dev $IFACE"*) ;;
        *)
          ip route replace "$dc_s" dev "$IFACE" 2>/dev/null || true
          dc_changed=1
          ;;
      esac
    done < "$DNS_ROUTES_FILE"
  fi

  [ "$dc_changed" -eq 0 ] || echo "DNS settings re-applied"
  grep -qF "$DNS_MARKER" /etc/resolv.conf 2>/dev/null
}

dns_restore() {
  if [ -f "$DNS_MODE_FILE" ]; then
    dr_target="$(cat "$DNS_TARGET_FILE" 2>/dev/null || true)"
    dr_mode="$(cat "$DNS_MODE_FILE" 2>/dev/null || true)"
    if [ -n "$dr_target" ] && [ "$dr_mode" = bind ]; then
      dr_base="$(cat "$DNS_BASEMOUNTS_FILE" 2>/dev/null || echo 0)"
      dr_i=0
      while [ "$(mount_count "$dr_target")" -gt "$dr_base" ] && [ "$dr_i" -lt 5 ]; do
        umount "$dr_target" 2>/dev/null || umount -l "$dr_target" 2>/dev/null || true
        dr_i=$((dr_i + 1))
      done
    elif [ -n "$dr_target" ] && [ "$dr_mode" = replace ] && [ -f "$DNS_ORIG" ]; then
      if grep -qF "$DNS_MARKER" "$dr_target" 2>/dev/null; then
        cat "$DNS_ORIG" > "$dr_target" 2>/dev/null || echo "WARNING: could not restore $dr_target"
      fi
    fi
    if grep -qF "$DNS_MARKER" /etc/resolv.conf 2>/dev/null; then
      echo "WARNING: /etc/resolv.conf still points to the tunnel DNS"
    else
      echo "original resolver restored"
    fi
  fi

  if [ -f "$DNS_ROUTES_FILE" ]; then
    while IFS= read -r dr_s; do
      [ -n "$dr_s" ] || continue
      ip route del "$dr_s" dev "$IFACE" 2>/dev/null || true
    done < "$DNS_ROUTES_FILE"
  fi
  rm -f "$DNS_MODE_FILE" "$DNS_TARGET_FILE" "$DNS_ORIG" "$DNS_BASEMOUNTS_FILE" "$DNS_ROUTES_FILE" "$DNS_RESOLV"
  return 0
}

# ---------------------------------------------------------------- kill switch

ks_enabled() {
  grep -qx 'killswitch=1' "$KILLSWITCH_CONF" 2>/dev/null
}

ks_active() {
  [ -f "$KS_STATE_FILE" ]
}

ipt4_usable() {
  command -v iptables >/dev/null 2>&1 && iptables -L OUTPUT -n >/dev/null 2>&1
}

ipt6_usable() {
  command -v ip6tables >/dev/null 2>&1 && ip6tables -L OUTPUT -n >/dev/null 2>&1
}

# off | on (firewall chain and routes) | routes (routes only: the kernel has
# no usable netfilter, the route kill switch alone blocks traffic)
ks_status_word() {
  if ! ks_enabled; then
    echo off
  elif ks_active; then
    echo on
  else
    echo routes
  fi
}

ks_lan_subnets() {
  ip -o -4 addr show 2>/dev/null | awk -v w="$IFACE" '
    {
      d = $2
      sub(/:$/, "", d)
      if (d == "lo" || d == w) next
      for (i = 3; i < NF; i++) if ($i == "inet") print $(i + 1)
    }'
}

ks_conf_ports() {
  peer_endpoints_from_conf | while read -r kp_pk kp_ep; do
    endpoint_port "$kp_ep"
  done | sort -u
}

ks_signature() {
  echo "mode=$1"
  endpoints_list | sort
  ks_lan_subnets | sort
  [ "$1" = boot ] && ks_conf_ports
  return 0
}

ks_rule_count() {
  "$1" -L "$KS_CHAIN" -n 2>/dev/null | awk 'NR > 2' | wc -l | tr -d ' '
}

# Builders append the full rule set; any failure aborts the install.
ks_build4() {
  kb="iptables -A $KS_CHAIN"
  $kb -o lo -j ACCEPT || return 1
  $kb -o "$IFACE" -j ACCEPT || return 1
  $kb -p udp --sport 68 --dport 67 -j ACCEPT || return 1
  endpoints_list > "$RUN/ks-endpoints"
  while read -r kb_fam kb_host kb_port; do
    [ "$kb_fam" = 4 ] || continue
    $kb -d "$kb_host" -p udp --dport "$kb_port" -j ACCEPT || return 1
  done < "$RUN/ks-endpoints"
  if [ "$1" = boot ]; then
    for kb_port in $(ks_conf_ports); do
      $kb -p udp --dport "$kb_port" -j ACCEPT || return 1
    done
    $kb -p udp --dport 53 -j ACCEPT || return 1
    $kb -p tcp --dport 53 -j ACCEPT || return 1
  else
    # DNS must use the tunnel; this also stops the LAN router from
    # forwarding plain DNS queries to the ISP.
    $kb -p udp --dport 53 -j DROP || return 1
    $kb -p tcp --dport 53 -j DROP || return 1
  fi
  for kb_net in $(ks_lan_subnets); do
    $kb -d "$kb_net" -j ACCEPT || return 1
  done
  $kb -d 224.0.0.0/4 -j ACCEPT || return 1
  $kb -d 255.255.255.255 -j ACCEPT || return 1
  $kb -j DROP || return 1
}

ks_build6() {
  kb="ip6tables -A $KS_CHAIN"
  $kb -o lo -j ACCEPT || return 1
  $kb -o "$IFACE" -j ACCEPT || return 1
  $kb -d fe80::/10 -j ACCEPT || return 1
  $kb -d ff00::/8 -j ACCEPT || return 1
  $kb -p icmpv6 -j ACCEPT || return 1
  endpoints_list > "$RUN/ks-endpoints"
  while read -r kb_fam kb_host kb_port; do
    [ "$kb_fam" = 6 ] || continue
    $kb -d "$kb_host" -p udp --dport "$kb_port" -j ACCEPT || return 1
  done < "$RUN/ks-endpoints"
  if [ "$1" = boot ]; then
    for kb_port in $(ks_conf_ports); do
      $kb -p udp --dport "$kb_port" -j ACCEPT || return 1
    done
  fi
  $kb -j DROP || return 1
}

# Builds the new rules behind the old ones, then deletes the old ones, so the
# chain is never empty while it is being refreshed. Only our own chain and
# one jump from OUTPUT are ever touched.
ks_install_table() {
  kt_tool="$1"
  "$kt_tool" -N "$KS_CHAIN" 2>/dev/null || true
  "$kt_tool" -L "$KS_CHAIN" -n >/dev/null 2>&1 || return 1
  kt_old="$(ks_rule_count "$kt_tool")"
  if ! "$2" "$3"; then
    kt_now="$(ks_rule_count "$kt_tool")"
    while [ "$kt_now" -gt "$kt_old" ]; do
      "$kt_tool" -D "$KS_CHAIN" "$kt_now" 2>/dev/null || break
      kt_now=$((kt_now - 1))
    done
    return 1
  fi
  kt_i=0
  while [ "$kt_i" -lt "$kt_old" ]; do
    "$kt_tool" -D "$KS_CHAIN" 1 2>/dev/null || break
    kt_i=$((kt_i + 1))
  done
  if ! "$kt_tool" -L OUTPUT -n 2>/dev/null | grep -q "$KS_CHAIN"; then
    "$kt_tool" -I OUTPUT 1 -j "$KS_CHAIN" || return 1
  fi
  return 0
}

# $1: strict (tunnel up) or boot (before the tunnel exists). Returns 1 when
# iptables cannot enforce the kill switch.
ks_apply() {
  ka_mode="${1:-strict}"
  if ! ipt4_usable; then
    echo "WARNING: kill switch: iptables is not usable on this TV"
    rm -f "$KS_STATE_FILE" "$KS_SIG_FILE"
    return 1
  fi
  if ! ks_install_table iptables ks_build4 "$ka_mode"; then
    echo "WARNING: kill switch: could not install the iptables rules"
    ks_remove
    return 1
  fi
  if ipt6_usable; then
    ks_install_table ip6tables ks_build6 "$ka_mode" ||
      echo "WARNING: kill switch: ip6tables rules failed; IPv6 stays disabled by sysctl"
  fi
  rm -f "$RUN/ks-endpoints"
  echo "$ka_mode" > "$KS_STATE_FILE"
  ks_signature "$ka_mode" > "$KS_SIG_FILE"
  return 0
}

ks_remove() {
  for kr_tool in iptables ip6tables; do
    command -v "$kr_tool" >/dev/null 2>&1 || continue
    kr_i=0
    while [ "$kr_i" -lt 10 ] && "$kr_tool" -D OUTPUT -j "$KS_CHAIN" 2>/dev/null; do
      kr_i=$((kr_i + 1))
    done
    "$kr_tool" -F "$KS_CHAIN" 2>/dev/null || true
    "$kr_tool" -X "$KS_CHAIN" 2>/dev/null || true
  done
  rm -f "$KS_STATE_FILE" "$KS_SIG_FILE" "$RUN/ks-endpoints"
  return 0
}

# Watchdog helper: keeps the rules in line with the setting, the current
# endpoints and the current LAN subnets.
ks_enforce() {
  if ks_enabled; then
    # Silent and idempotent: the routes must survive any network change.
    ks_routes_apply >/dev/null 2>&1 || echo "WARNING: kill switch routes could not be added"
    ipt4_usable || return 0
    if ! ks_active ||
      [ "$(cat "$KS_STATE_FILE" 2>/dev/null)" != strict ] ||
      ! iptables -L OUTPUT -n 2>/dev/null | grep -q "$KS_CHAIN" ||
      [ "$(ks_signature strict)" != "$(cat "$KS_SIG_FILE" 2>/dev/null)" ]; then
      ks_apply strict && echo "kill switch rules refreshed"
    fi
  elif ks_active || ks_routes_active; then
    ks_remove
    ks_routes_remove
    echo "kill switch removed"
  fi
  return 0
}

# ---------------------------------------------------------------- teardown

restore_default_route() {
  if ! ip route show default 2>/dev/null | grep -q default; then
    rd_gw="$(cat "$GWFILE" 2>/dev/null || true)"
    rd_dev="$(cat "$DEVFILE" 2>/dev/null || true)"
    if [ -n "$rd_gw" ] && [ -n "$rd_dev" ]; then
      ip route replace default via "$rd_gw" dev "$rd_dev" 2>/dev/null || true
    fi
  fi
}

# $1 = 1 keeps traffic blocked (kill switch): the kill switch chain, the DNS
# redirection, disabled IPv6 and the endpoint routes stay in place, and
# blackhole routes are added when iptables is not usable.
teardown_tunnel() {
  tt_keep="${1:-0}"

  echo "== deleting applied WireGuard routes =="
  if [ -f "$APPLIED_ROUTES_FILE" ]; then
    while read -r tt_r; do
      [ -n "$tt_r" ] || continue
      ip route del "$tt_r" dev "$IFACE" 2>/dev/null || true
    done < "$APPLIED_ROUTES_FILE"
    rm -f "$APPLIED_ROUTES_FILE"
  fi
  if [ -f "$PROBE_ROUTE_FILE" ]; then
    ip route del "$(cat "$PROBE_ROUTE_FILE")" dev "$IFACE" 2>/dev/null || true
    rm -f "$PROBE_ROUTE_FILE"
  fi

  if [ "$tt_keep" != 1 ]; then
    echo "== deleting endpoint routes =="
    if [ -f "$ENDPOINTS_FILE" ]; then
      while read -r tt_a tt_b; do
        [ -n "$tt_a" ] || continue
        if [ -z "$tt_b" ]; then
          tt_b="$tt_a"
          tt_a=4
        fi
        route_del_pin "$tt_a" "$tt_b"
      done < "$ENDPOINTS_FILE"
      rm -f "$ENDPOINTS_FILE"
    fi
    v6block_remove
  fi

  echo "== removing interface =="
  ip link del "$IFACE" 2>/dev/null || true

  echo "== stopping wireguard-go =="
  if [ -f "$PIDFILE" ]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
  killall wireguard-go 2>/dev/null || true
  rm -f "/var/run/wireguard/$IFACE.sock"
  rm -f "$SETCONF_FILE" "$ENDPOINTS_FILE.new" "$RUN/endpoints.now" "$RUN/ks-endpoints" \
    "$RUN/peer-endpoints" "$RUN/watchdog.out"

  if [ "$tt_keep" = 1 ]; then
    echo "== kill switch: keeping traffic blocked =="
    ks_routes_apply || echo "WARNING: kill switch routes could not be added"
  else
    echo "== restoring DNS =="
    dns_restore
    echo "== restoring IPv6 =="
    ipv6_restore_all
    echo "== removing kill switch =="
    ks_remove
    ks_routes_remove
    echo "== restoring original default route if needed =="
    restore_default_route
  fi
  return 0
}
