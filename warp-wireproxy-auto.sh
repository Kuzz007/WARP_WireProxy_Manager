#!/usr/bin/env bash
# warp-wireproxy-auto.sh
# Auto installer/configurator for Cloudflare WARP via wireproxy.
#
# What it does:
#   - installs dependencies
#   - installs WARP WireProxy via fscarmen/warp if missing
#   - creates wireproxy.service if binary/configs exist but systemd unit is missing
#   - ensures wireproxy SOCKS5 listens on 127.0.0.1:40000
#   - tests WARP endpoints
#   - selects the fastest endpoint with warp=on
#   - prints ready-to-paste 3x-ui/Xray outbound/routing blocks
#   - prints zapret4rocket UDP ports
#
# Run:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Kuzz007/test/main/warp-wireproxy-auto.sh)

set -Eeuo pipefail

SOCKS_PORT="40000"
SOCKS_HOST="127.0.0.1"
INSTALL_WARP="1"

WARP_CONF="/etc/wireguard/warp.conf"
PROXY_CONF="/etc/wireguard/proxy.conf"
SERVICE_FILE="/etc/systemd/system/wireproxy.service"

FSCARMEN_MENU_URL="https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh"
TEST_URL="https://www.cloudflare.com/cdn-cgi/trace"

RESULT_FILE="/tmp/warp_endpoint_results.$$"

BEST_ENDPOINT=""
BEST_TIME=""
BEST_TRACE=""
BEST_COLO=""
BEST_LOC=""

ZAPRET_PORTS="443,2408,1843,1010,500,1701,4500,4443,8443,8095"

DEFAULT_ENDPOINTS=(
  "162.159.192.244:1843"
  "162.159.195.100:1010"
  "162.159.193.10:2408"
  "162.159.193.5:2408"
  "188.114.96.10:2408"
  "188.114.97.10:2408"
  "engage.cloudflareclient.com:2408"
)

ENDPOINTS=("${DEFAULT_ENDPOINTS[@]}")

log()  { printf '\033[1;36m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR]\033[0m %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Usage:
  bash $0 [options]

Options:
  --port <port>             SOCKS5 port for wireproxy. Default: 40000
  --host <host>             SOCKS5 bind host. Default: 127.0.0.1
  --endpoints "<list>"      Space/comma separated endpoint list
  --no-install              Do not run fscarmen installer if wireproxy is missing
  -h, --help                Show help

Examples:
  bash $0
  bash $0 --port 40000
  bash $0 --no-install
  bash $0 --endpoints "162.159.192.244:1843 162.159.195.100:1010"
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        SOCKS_PORT="${2:-}"
        shift 2
        ;;
      --host)
        SOCKS_HOST="${2:-}"
        shift 2
        ;;
      --endpoints)
        local raw="${2:-}"
        raw="${raw//,/ }"
        # shellcheck disable=SC2206
        ENDPOINTS=($raw)
        shift 2
        ;;
      --no-install)
        INSTALL_WARP="0"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Run as root."
    exit 1
  fi
}

install_deps_apt() {
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    wget \
    ca-certificates \
    grep \
    sed \
    gawk \
    coreutils \
    iproute2 \
    systemd
  if ! command -v awk >/dev/null 2>&1 && command -v gawk >/dev/null 2>&1; then
    ln -sf "$(command -v gawk)" /usr/local/bin/awk
  fi
}

install_deps_dnf() {
  dnf install -y curl wget ca-certificates grep sed gawk coreutils iproute systemd
}

install_deps_yum() {
  yum install -y curl wget ca-certificates grep sed gawk coreutils iproute systemd
}

install_deps_apk() {
  apk add --no-cache curl wget ca-certificates grep sed gawk coreutils iproute2
}

detect_os_and_install_deps() {
  log "Installing/checking dependencies..."
  if command -v apt-get >/dev/null 2>&1; then
    install_deps_apt
  elif command -v dnf >/dev/null 2>&1; then
    install_deps_dnf
  elif command -v yum >/dev/null 2>&1; then
    install_deps_yum
  elif command -v apk >/dev/null 2>&1; then
    install_deps_apk
  else
    warn "Unknown package manager. Make sure curl wget grep sed awk ip ss systemctl are installed."
  fi

  local missing=()
  for cmd in curl wget grep sed awk ip ss systemctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    err "Missing required commands: ${missing[*]}"
    exit 1
  fi
  ok "Dependencies are ready."
}

find_wireproxy_bin() {
  if command -v wireproxy >/dev/null 2>&1; then
    command -v wireproxy
    return 0
  fi
  for p in /usr/bin/wireproxy /usr/local/bin/wireproxy /opt/bin/wireproxy; do
    if [[ -x "$p" ]]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

wireproxy_unit_exists() {
  systemctl list-unit-files 2>/dev/null | grep -q '^wireproxy\.service' || [[ -f "$SERVICE_FILE" ]] || [[ -f /usr/lib/systemd/system/wireproxy.service ]]
}

wireproxy_install_exists() {
  find_wireproxy_bin >/dev/null 2>&1 && [[ -f "$WARP_CONF" && -f "$PROXY_CONF" ]]
}

create_wireproxy_service_if_missing() {
  local bin
  if wireproxy_unit_exists; then
    ok "wireproxy.service exists."
    return 0
  fi

  if ! bin="$(find_wireproxy_bin)"; then
    warn "wireproxy binary not found, cannot create service yet."
    return 1
  fi

  if [[ ! -f "$PROXY_CONF" ]]; then
    warn "$PROXY_CONF not found, cannot create service yet."
    return 1
  fi

  log "wireproxy binary/configs exist, but systemd unit is missing. Creating $SERVICE_FILE"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=WireProxy for WARP
Documentation=https://github.com/pufferffish/wireproxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$bin -c $PROXY_CONF
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable wireproxy >/dev/null 2>&1 || true
  ok "Created and enabled wireproxy.service"
}

install_wireproxy_if_needed() {
  if wireproxy_install_exists; then
    ok "wireproxy binary and config files already exist."
    create_wireproxy_service_if_missing || true
    return 0
  fi

  if [[ "$INSTALL_WARP" != "1" ]]; then
    err "wireproxy/config not found and --no-install was used."
    err "Need binary wireproxy plus:"
    err "$WARP_CONF"
    err "$PROXY_CONF"
    exit 1
  fi

  log "wireproxy or configs are missing."
  log "Running fscarmen WARP WireProxy installer..."
  warn "External installer may ask questions depending on the OS/environment."

  cd /root
  wget -N "$FSCARMEN_MENU_URL" -O /root/menu.sh

  bash /root/menu.sh w || {
    err "fscarmen installer failed."
    err "Manual install command:"
    err "wget -N $FSCARMEN_MENU_URL -O /root/menu.sh && bash /root/menu.sh w"
    exit 1
  }

  if ! wireproxy_install_exists; then
    err "After install, expected wireproxy binary/configs were not found."
    err "Check:"
    err "  command -v wireproxy"
    err "  ls -la /etc/wireguard/"
    exit 1
  fi

  create_wireproxy_service_if_missing || true
  ok "WireProxy installation is ready."
}

backup_configs() {
  mkdir -p /root/warp-wireproxy-backup
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  [[ -f "$WARP_CONF" ]] && cp -a "$WARP_CONF" "/root/warp-wireproxy-backup/warp.conf.$ts.bak"
  [[ -f "$PROXY_CONF" ]] && cp -a "$PROXY_CONF" "/root/warp-wireproxy-backup/proxy.conf.$ts.bak"
  [[ -f "$SERVICE_FILE" ]] && cp -a "$SERVICE_FILE" "/root/warp-wireproxy-backup/wireproxy.service.$ts.bak"
  ok "Backups saved to /root/warp-wireproxy-backup/"
}

set_endpoint() {
  local ep="$1"
  if grep -qi '^Endpoint[[:space:]]*=' "$WARP_CONF"; then
    sed -i "s#^Endpoint[[:space:]]*=.*#Endpoint = $ep#I" "$WARP_CONF"
  else
    printf '\nEndpoint = %s\n' "$ep" >> "$WARP_CONF"
  fi
}

ensure_proxy_port() {
  log "Ensuring wireproxy SOCKS5 listens on ${SOCKS_HOST}:${SOCKS_PORT}..."

  if [[ ! -f "$PROXY_CONF" ]]; then
    err "Missing $PROXY_CONF"
    exit 1
  fi

  if grep -q '^\[Socks5\]' "$PROXY_CONF"; then
    if awk '
      /^\[Socks5\]/{insec=1; next}
      /^\[/{insec=0}
      insec && /^[[:space:]]*BindAddress[[:space:]]*=/{found=1}
      END{exit !found}
    ' "$PROXY_CONF"; then
      awk -v bind="${SOCKS_HOST}:${SOCKS_PORT}" '
        BEGIN{insec=0}
        /^\[Socks5\]/{insec=1; print; next}
        /^\[/{insec=0; print; next}
        insec && /^[[:space:]]*BindAddress[[:space:]]*=/{print "BindAddress = " bind; next}
        {print}
      ' "$PROXY_CONF" > "${PROXY_CONF}.tmp"
      mv "${PROXY_CONF}.tmp" "$PROXY_CONF"
    else
      awk -v bind="${SOCKS_HOST}:${SOCKS_PORT}" '
        /^\[Socks5\]/{print; print "BindAddress = " bind; next}
        {print}
      ' "$PROXY_CONF" > "${PROXY_CONF}.tmp"
      mv "${PROXY_CONF}.tmp" "$PROXY_CONF"
    fi
  else
    cat >> "$PROXY_CONF" <<EOF

[Socks5]
BindAddress = ${SOCKS_HOST}:${SOCKS_PORT}
EOF
  fi

  ok "SOCKS5 bind address set to ${SOCKS_HOST}:${SOCKS_PORT}"
}

restart_wireproxy() {
  create_wireproxy_service_if_missing || true

  if wireproxy_unit_exists; then
    systemctl daemon-reload || true
    systemctl enable wireproxy >/dev/null 2>&1 || true
    systemctl restart wireproxy
    sleep 2
  else
    err "wireproxy.service not found and could not be created."
    err "Diagnostics:"
    err "  command -v wireproxy"
    err "  ls -la /etc/wireguard/"
    exit 1
  fi
}

check_port() {
  if ss -lntup 2>/dev/null | grep -q "${SOCKS_HOST}:${SOCKS_PORT}"; then
    ok "SOCKS5 is listening on ${SOCKS_HOST}:${SOCKS_PORT}"
  else
    warn "SOCKS5 port is not visible with ss. Current listeners:"
    ss -lntup 2>/dev/null | grep -E 'wireproxy|40000|1080' || true
    warn "wireproxy status:"
    systemctl status wireproxy --no-pager -l | head -80 || true
  fi
}

test_endpoint() {
  local ep="$1"
  local trace_file="/tmp/warp_trace.$$"
  local rc=0

  set_endpoint "$ep"
  restart_wireproxy

  curl -m 15 -sS -x "socks5h://${SOCKS_HOST}:${SOCKS_PORT}" \
    -w '\n__TIME_TOTAL__=%{time_total}\n__HTTP_CODE__=%{http_code}\n' \
    "$TEST_URL" > "$trace_file" 2>/dev/null || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    printf '%s\tFAIL\tcurl_rc=%s\t-\t-\t-\t-\n' "$ep" "$rc" >> "$RESULT_FILE"
    rm -f "$trace_file"
    return 1
  fi

  local warp ip colo loc time_total http_code
  warp="$(grep -m1 '^warp=' "$trace_file" | cut -d= -f2- || true)"
  ip="$(grep -m1 '^ip=' "$trace_file" | cut -d= -f2- || true)"
  colo="$(grep -m1 '^colo=' "$trace_file" | cut -d= -f2- || true)"
  loc="$(grep -m1 '^loc=' "$trace_file" | cut -d= -f2- || true)"
  time_total="$(grep -m1 '^__TIME_TOTAL__=' "$trace_file" | cut -d= -f2- || true)"
  http_code="$(grep -m1 '^__HTTP_CODE__=' "$trace_file" | cut -d= -f2- || true)"

  if [[ "$http_code" == "200" && "$warp" == "on" && -n "$time_total" ]]; then
    printf '%s\tOK\t%s\t%s\t%s\t%s\t%s\n' "$ep" "$time_total" "$ip" "$colo" "$loc" "$warp" >> "$RESULT_FILE"
    rm -f "$trace_file"
    return 0
  fi

  printf '%s\tFAIL\thttp=%s time=%s ip=%s colo=%s loc=%s warp=%s\n' \
    "$ep" "$http_code" "$time_total" "$ip" "$colo" "$loc" "$warp" >> "$RESULT_FILE"

  rm -f "$trace_file"
  return 1
}

select_best_endpoint() {
  log "Testing WARP endpoints..."
  : > "$RESULT_FILE"

  local ep
  for ep in "${ENDPOINTS[@]}"; do
    [[ -z "$ep" ]] && continue
    log "Testing $ep"
    if test_endpoint "$ep"; then
      ok "$ep works"
    else
      warn "$ep failed"
    fi
  done

  echo
  echo "=== Endpoint test results ==="
  if command -v column >/dev/null 2>&1; then
    column -t -s $'\t' "$RESULT_FILE" || cat "$RESULT_FILE"
  else
    cat "$RESULT_FILE"
  fi
  echo

  local best_line
  best_line="$(awk -F'\t' '$2=="OK"{print $0}' "$RESULT_FILE" | sort -t $'\t' -k3,3n | head -n1 || true)"

  if [[ -z "$best_line" ]]; then
    err "No endpoint returned warp=on."
    err "Try adding endpoints from your WARP scanner:"
    err "bash $0 --endpoints \"IP1:PORT IP2:PORT\""
    exit 1
  fi

  BEST_ENDPOINT="$(printf '%s' "$best_line" | awk -F'\t' '{print $1}')"
  BEST_TIME="$(printf '%s' "$best_line" | awk -F'\t' '{print $3}')"
  BEST_COLO="$(printf '%s' "$best_line" | awk -F'\t' '{print $5}')"
  BEST_LOC="$(printf '%s' "$best_line" | awk -F'\t' '{print $6}')"

  set_endpoint "$BEST_ENDPOINT"
  restart_wireproxy

  ok "Selected fastest endpoint: $BEST_ENDPOINT time_total=$BEST_TIME colo=$BEST_COLO loc=$BEST_LOC"
}

final_check() {
  log "Final WARP check..."
  BEST_TRACE="$(curl -m 15 -s -x "socks5h://${SOCKS_HOST}:${SOCKS_PORT}" "$TEST_URL" | grep -E 'ip=|colo=|loc=|warp=' || true)"
  echo "$BEST_TRACE"

  if ! echo "$BEST_TRACE" | grep -q '^warp=on'; then
    err "Final check did not show warp=on."
    err "Current endpoint:"
    grep -i '^Endpoint' "$WARP_CONF" || true
    err "wireproxy status:"
    systemctl status wireproxy --no-pager -l | head -80 || true
    exit 1
  fi

  ok "Final check passed: warp=on"
}

print_3xui_blocks() {
  local endpoint_port
  endpoint_port="${BEST_ENDPOINT##*:}"

  cat <<EOF

============================================================
DONE
============================================================

Selected WARP endpoint:
  $BEST_ENDPOINT

Current local SOCKS5:
  socks5://${SOCKS_HOST}:${SOCKS_PORT}

Cloudflare trace:
$(echo "$BEST_TRACE" | sed 's/^/  /')

------------------------------------------------------------
3x-ui / Xray outbounds
------------------------------------------------------------

Add these outbounds:

{
  "tag": "WARP-socks5",
  "protocol": "socks",
  "settings": {
    "servers": [
      {
        "address": "${SOCKS_HOST}",
        "port": ${SOCKS_PORT}
      }
    ]
  }
},
{
  "tag": "WARP",
  "protocol": "freedom",
  "settings": {
    "domainStrategy": "UseIPv4"
  },
  "proxySettings": {
    "tag": "WARP-socks5"
  }
}

------------------------------------------------------------
3x-ui / Xray routing example
------------------------------------------------------------

Route selected domains through WARP:

{
  "type": "field",
  "domain": [
    "domain:openai.com",
    "domain:chatgpt.com",
    "domain:oaistatic.com",
    "domain:oaiusercontent.com"
  ],
  "outboundTag": "WARP"
}

Important:
  Use outboundTag "WARP", not "WARP-socks5".

------------------------------------------------------------
zapret4rocket
------------------------------------------------------------

Minimum UDP port for current endpoint:
  $endpoint_port

Recommended full line:
  NFQWS_PORTS_UDP=$ZAPRET_PORTS

Open config:
  nano /opt/zapret/config

Restart:
  /opt/zapret/init.d/sysv/zapret restart

or:
  systemctl restart zapret

------------------------------------------------------------
Useful checks
------------------------------------------------------------

grep -i '^Endpoint' /etc/wireguard/warp.conf

systemctl status wireproxy --no-pager -l | head -60

ss -lntup | grep ':${SOCKS_PORT}'

curl -m 10 -s -x socks5h://${SOCKS_HOST}:${SOCKS_PORT} https://www.cloudflare.com/cdn-cgi/trace | grep -E 'ip=|colo=|loc=|warp='

Backups:
  /root/warp-wireproxy-backup/

EOF
}

cleanup() {
  rm -f "$RESULT_FILE" "/tmp/warp_trace.$$" 2>/dev/null || true
}

main() {
  trap cleanup EXIT

  parse_args "$@"
  require_root
  detect_os_and_install_deps
  install_wireproxy_if_needed
  backup_configs
  ensure_proxy_port
  restart_wireproxy
  check_port
  select_best_endpoint
  final_check
  print_3xui_blocks
}

main "$@"
