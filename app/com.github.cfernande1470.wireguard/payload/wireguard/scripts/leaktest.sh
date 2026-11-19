#!/bin/sh
# Checks that IPv4 uses the tunnel, IPv6 cannot leave, and DNS goes to the
# tunnel DNS server. Prints PASS, FAIL, WARN and INFO lines and a RESULT line.

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/lib.sh"

FAILS=0
WARNS=0

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; FAILS=$((FAILS + 1)); }
warn() { echo "WARN  $*"; WARNS=$((WARNS + 1)); }
info() { echo "INFO  $*"; }

echo "== Leak test =="

if ! tunnel_running; then
  fail "the VPN is not running"
  echo "RESULT=FAIL"
  exit 0
fi

# IPv4
route4="$(ip route get 1.1.1.1 2>/dev/null | head -1)"
case "$route4" in
  *"dev $IFACE"*) pass "IPv4 internet traffic uses the tunnel ($IFACE)" ;;
  *) fail "IPv4 internet traffic leaves outside the tunnel: $route4" ;;
esac

pub="$("$HERE/summary.sh" pubip | sed -n 's/^pubip=//p')"
if [ -n "$pub" ]; then
  info "public IPv4: $pub"
else
  warn "public IPv4 check failed (no answer from the IP check service)"
fi

# IPv6
v6_leak=0
if ip -6 route get 2001:4860:4860::8888 >/dev/null 2>&1; then
  case "$(ip -6 route get 2001:4860:4860::8888 2>/dev/null | head -1)" in
    *unreachable*|*prohibit*|*blackhole*) ;;
    *)
      if command -v curl >/dev/null 2>&1; then
        v6="$(curl -6 -s --max-time 5 https://api64.ipify.org 2>/dev/null || curl -6 -s --max-time 5 http://api64.ipify.org 2>/dev/null || true)"
        case "$v6" in
          *:*) v6_leak=1 ;;
        esac
      fi
      ;;
  esac
fi
if [ "$v6_leak" = 1 ]; then
  fail "IPv6 reaches the internet outside the tunnel: $v6"
else
  pass "IPv6 is blocked or unreachable"
fi

# DNS
in_use="$(sed -n 's/^[[:space:]]*nameserver[[:space:]]*\([^[:space:]]*\).*/\1/p' /etc/resolv.conf 2>/dev/null | tr '\n' ' ')"
info "resolver in use: ${in_use:-none}"
if [ -s "$DNS_SERVERS_FILE" ]; then
  dns_ok=1
  for s in $in_use; do
    grep -qxF "$s" "$DNS_SERVERS_FILE" || dns_ok=0
  done
  [ -n "$in_use" ] || dns_ok=0
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    case "$(ip route get "$s" 2>/dev/null | head -1)" in
      *"dev $IFACE"*) ;;
      *) dns_ok=0; info "DNS $s is not routed through $IFACE" ;;
    esac
  done < "$DNS_SERVERS_FILE"
  if [ "$dns_ok" = 1 ]; then
    pass "DNS uses the tunnel DNS server ($(tr '\n' ' ' < "$DNS_SERVERS_FILE"))"
  else
    fail "DNS does not use the tunnel DNS server ($(tr '\n' ' ' < "$DNS_SERVERS_FILE"))"
  fi
else
  warn "no DNS server in the VPN config: lookups use the TV's normal resolver"
fi

# Kill switch
if ks_enabled; then
  ks_routes="$(ip route 2>/dev/null | grep -cE '^blackhole (0[.]0[.]0[.]0|128[.]0[.]0[.]0)/1')"
  if [ "$ks_routes" -ge 2 ]; then
    pass "kill switch routes in place (blackhole 0.0.0.0/1 and 128.0.0.0/1 behind wg0)"
  else
    fail "kill switch is on but its blackhole routes are missing"
  fi
  case "$(ks_status_word)" in
    on) pass "kill switch firewall chain active" ;;
    *) info "kill switch runs on routes only (no usable iptables)" ;;
  esac
else
  info "kill switch off"
fi

if [ "$FAILS" -gt 0 ]; then
  echo "RESULT=FAIL"
elif [ "$WARNS" -gt 0 ]; then
  echo "RESULT=WARN"
else
  echo "RESULT=PASS"
fi
