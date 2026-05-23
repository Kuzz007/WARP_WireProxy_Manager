#!/usr/bin/env bash
# warp-wireproxy-native.sh
# Полностью неинтерактивный установщик Cloudflare WARP + wireproxy + SOCKS5 для 3x-ui/Xray.
#
# Что делает:
#   - не использует fscarmen/menu.sh;
#   - сам регистрирует WARP-устройство через API Cloudflare;
#   - сам создаёт /etc/wireguard/warp.conf и /etc/wireguard/proxy.conf;
#   - сам ставит wireproxy из GitHub Releases, а если релиз не найден — пробует собрать через Go;
#   - сам создаёт systemd service;
#   - сам сканирует WARP endpoint'ы и выбирает самый быстрый, где warp=on;
#   - кэширует хорошие и плохие endpoint'ы;
#   - умеет режим --check: быстро проверить WARP и при поломке подменить endpoint;
#   - в конце печатает готовые блоки для 3x-ui/Xray и zapret4rocket.
#
# Установка:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warp-wireproxy-native.sh)
#
# Проверка/ремонт endpoint:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warp-wireproxy-native.sh) --check

set -Eeuo pipefail

VERSION="1.1.0"

SOCKS_HOST="127.0.0.1"
SOCKS_PORT="40000"
SCAN_COUNT="50"
USE_CUSTOM_ENDPOINTS="0"
FORCE_REGISTER="0"
CHECK_ONLY="0"

WG_DIR="/etc/wireguard"
WARP_CONF="$WG_DIR/warp.conf"
PROXY_CONF="$WG_DIR/proxy.conf"
ACCOUNT_JSON="$WG_DIR/warp-account.json"
PRIVATE_KEY_FILE="$WG_DIR/warp-private.key"
GOOD_ENDPOINTS_FILE="$WG_DIR/warp-endpoints.good"
BAD_ENDPOINTS_FILE="$WG_DIR/warp-endpoints.bad"
SERVICE_FILE="/etc/systemd/system/wireproxy.service"
TEST_URL="https://www.cloudflare.com/cdn-cgi/trace"
RESULT_FILE="/tmp/warp_native_results.$$"
CANDIDATES_FILE="/tmp/warp_native_candidates.$$"

BEST_ENDPOINT=""
BEST_TIME=""
BEST_TRACE=""
BEST_COLO=""
BEST_LOC=""

ZAPRET_PORTS="443,2408,1843,1010,500,1701,4500,4443,8443,8095"

WARP_PREFIXES=(
  "162.159.192"
  "162.159.193"
  "162.159.194"
  "162.159.195"

  "188.114.96"
  "188.114.97"
  "188.114.98"
  "188.114.99"

  "8.34.146"
  "8.39.214"
  "8.39.204"
  "8.6.112"
  "8.35.211"
  "8.39.125"
  "8.47.69"
)
WARP_PORTS=(
  500 854 859 864 878 880 890 891 894 903
  908 928 934 939 942 943 945 946 955 968
  987 988 1002 1010 1014 1018 1070 1074 1180 1387
  1701 1843 2371 2408 2506 3138 3476 3581 3854 4177
  4198 4233 4500 5279 5956 7103 7152 7156 7281 7559
  8319 8742 8854 8886
)
CUSTOM_ENDPOINTS=()

log()  { printf '\033[1;36m[ИНФО]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ОК]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ВНИМАНИЕ]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ОШИБКА]\033[0m %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Использование:
  bash $0 [опции]

Опции:
  --check                   Только проверить WARP. Если warp=on нет — пересканировать и подменить endpoint.
  --port <порт>             Локальный SOCKS5-порт. По умолчанию: 40000
  --host <хост>             Bind-адрес SOCKS5. По умолчанию: 127.0.0.1
  --scan-count <число>      Сколько случайных endpoint'ов проверить. По умолчанию: 50
  --ports "список"          Порты для сканирования, через пробел или запятую
  --endpoints "список"      Проверить конкретные endpoint'ы вместо автосканирования
  --force-register          Создать новый WARP-аккаунт, даже если старый уже есть
  --version                 Показать версию
  -h, --help                Показать справку

Примеры:
  bash $0
  bash $0 --check
  bash $0 --check --scan-count 25
  bash $0 --scan-count 100
  bash $0 --ports "2408,1843,1010,500,1701,4500"
  bash $0 --endpoints "162.159.192.244:1843 162.159.195.100:1010"

Для cron/systemd можно использовать:
  bash $0 --check --scan-count 25
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --check)
        CHECK_ONLY="1"
        shift
        ;;
      --port)
        SOCKS_PORT="${2:-}"
        shift 2
        ;;
      --host)
        SOCKS_HOST="${2:-}"
        shift 2
        ;;
      --scan-count)
        SCAN_COUNT="${2:-}"
        shift 2
        ;;
      --ports)
        local raw_ports="${2:-}"
        raw_ports="${raw_ports//,/ }"
        # shellcheck disable=SC2206
        WARP_PORTS=($raw_ports)
        shift 2
        ;;
      --endpoints)
        local raw_eps="${2:-}"
        raw_eps="${raw_eps//,/ }"
        # shellcheck disable=SC2206
        CUSTOM_ENDPOINTS=($raw_eps)
        USE_CUSTOM_ENDPOINTS="1"
        shift 2
        ;;
      --force-register)
        FORCE_REGISTER="1"
        shift
        ;;
      --version|-v)
        echo "warp-wireproxy-native.sh v$VERSION"
        exit 0
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Неизвестная опция: $1"
        usage
        exit 1
        ;;
    esac
  done
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Запусти от root."
    exit 1
  fi
}

install_deps_apt() {
  apt-get update -y || warn "apt update завершился с ошибкой. Продолжаю: часто причина в сломанном стороннем репозитории."
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget ca-certificates grep sed gawk coreutils iproute2 systemd wireguard-tools python3 tar unzip git || {
      err "Не удалось установить зависимости через apt. Проверь apt update и сторонние репозитории."
      exit 1
    }
  if ! command -v awk >/dev/null 2>&1 && command -v gawk >/dev/null 2>&1; then
    ln -sf "$(command -v gawk)" /usr/local/bin/awk
  fi
}

install_deps_dnf() { dnf install -y curl wget ca-certificates grep sed gawk coreutils iproute systemd wireguard-tools python3 tar unzip git; }
install_deps_yum() { yum install -y curl wget ca-certificates grep sed gawk coreutils iproute systemd wireguard-tools python3 tar unzip git; }
install_deps_apk() { apk add --no-cache curl wget ca-certificates grep sed gawk coreutils iproute2 wireguard-tools python3 tar unzip git; }

install_deps() {
  log "Проверяю зависимости..."
  if command -v apt-get >/dev/null 2>&1; then
    install_deps_apt
  elif command -v dnf >/dev/null 2>&1; then
    install_deps_dnf
  elif command -v yum >/dev/null 2>&1; then
    install_deps_yum
  elif command -v apk >/dev/null 2>&1; then
    install_deps_apk
  else
    warn "Неизвестный пакетный менеджер. Убедись, что curl, python3, wg и systemctl установлены."
  fi

  local missing=()
  for cmd in curl wget grep sed awk python3 wg ip ss systemctl sort head cut uniq tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    err "Не найдены команды: ${missing[*]}"
    exit 1
  fi
  ok "Зависимости готовы."
}

find_wireproxy_bin() {
  if command -v wireproxy >/dev/null 2>&1; then command -v wireproxy; return 0; fi
  for p in /usr/local/bin/wireproxy /usr/bin/wireproxy /opt/bin/wireproxy; do
    [[ -x "$p" ]] && echo "$p" && return 0
  done
  return 1
}

install_wireproxy_from_release() {
  local arch arch_re url tmp tmpdir bin
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch_re="amd64|x86_64" ;;
    aarch64|arm64) arch_re="arm64|aarch64" ;;
    armv7l|armv7) arch_re="armv7|arm" ;;
    *) arch_re="$arch" ;;
  esac

  log "Пытаюсь скачать wireproxy из GitHub Releases для архитектуры: $arch"

  url="$(python3 - "$arch_re" <<'PY'
import json, re, sys, urllib.request
arch_re = sys.argv[1]
api = 'https://api.github.com/repos/pufferffish/wireproxy/releases/latest'
try:
    data = json.load(urllib.request.urlopen(api, timeout=20))
except Exception:
    sys.exit(1)
assets = data.get('assets', [])
for a in assets:
    u = a.get('browser_download_url', '')
    name = a.get('name', '')
    s = (name + ' ' + u).lower()
    if 'linux' in s and re.search(arch_re, s):
        print(u)
        sys.exit(0)
sys.exit(1)
PY
)" || true

  [[ -z "$url" ]] && return 1

  tmp="/tmp/wireproxy-download.$$"
  tmpdir="/tmp/wireproxy-extract.$$"
  mkdir -p "$tmpdir"
  curl -fL "$url" -o "$tmp"

  if [[ "$url" == *.zip ]]; then
    unzip -q "$tmp" -d "$tmpdir"
  elif [[ "$url" == *.tar.gz || "$url" == *.tgz ]]; then
    tar -xzf "$tmp" -C "$tmpdir"
  else
    cp "$tmp" "$tmpdir/wireproxy"
  fi

  bin="$(find "$tmpdir" -type f -name 'wireproxy' -o -type f -name 'wireproxy-*' | head -n1 || true)"
  if [[ -z "$bin" ]]; then
    return 1
  fi

  install -m 0755 "$bin" /usr/local/bin/wireproxy
  rm -rf "$tmp" "$tmpdir"
  ok "wireproxy установлен: /usr/local/bin/wireproxy"
}

install_wireproxy_from_go() {
  warn "Готового релиза wireproxy не нашёл. Пробую собрать через Go."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y golang-go
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y golang
  elif command -v yum >/dev/null 2>&1; then
    yum install -y golang
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache go
  fi

  if ! command -v go >/dev/null 2>&1; then
    err "Go не установлен, собрать wireproxy не удалось."
    exit 1
  fi

  GOBIN=/usr/local/bin go install github.com/pufferffish/wireproxy/cmd/wireproxy@latest
  if ! find_wireproxy_bin >/dev/null 2>&1; then
    err "wireproxy не появился после go install."
    exit 1
  fi
  ok "wireproxy собран и установлен."
}

ensure_wireproxy_installed() {
  if find_wireproxy_bin >/dev/null 2>&1; then
    ok "wireproxy уже установлен: $(find_wireproxy_bin)"
    return 0
  fi
  install_wireproxy_from_release || install_wireproxy_from_go
}

backup_existing() {
  mkdir -p /root/warp-wireproxy-native-backup
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  [[ -f "$WARP_CONF" ]] && cp -a "$WARP_CONF" "/root/warp-wireproxy-native-backup/warp.conf.$ts.bak"
  [[ -f "$PROXY_CONF" ]] && cp -a "$PROXY_CONF" "/root/warp-wireproxy-native-backup/proxy.conf.$ts.bak"
  [[ -f "$ACCOUNT_JSON" ]] && cp -a "$ACCOUNT_JSON" "/root/warp-wireproxy-native-backup/warp-account.json.$ts.bak"
  [[ -f "$SERVICE_FILE" ]] && cp -a "$SERVICE_FILE" "/root/warp-wireproxy-native-backup/wireproxy.service.$ts.bak"
  [[ -f "$GOOD_ENDPOINTS_FILE" ]] && cp -a "$GOOD_ENDPOINTS_FILE" "/root/warp-wireproxy-native-backup/warp-endpoints.good.$ts.bak"
  [[ -f "$BAD_ENDPOINTS_FILE" ]] && cp -a "$BAD_ENDPOINTS_FILE" "/root/warp-wireproxy-native-backup/warp-endpoints.bad.$ts.bak"
  ok "Бэкапы сохранены в /root/warp-wireproxy-native-backup/"
}

register_warp_account() {
  mkdir -p "$WG_DIR"
  chmod 700 "$WG_DIR"

  if [[ "$FORCE_REGISTER" != "1" && -f "$ACCOUNT_JSON" && -f "$PRIVATE_KEY_FILE" ]]; then
    ok "WARP-аккаунт уже есть. Использую существующий $ACCOUNT_JSON"
    return 0
  fi

  log "Генерирую WireGuard ключи и регистрирую WARP-устройство через API Cloudflare..."
  local private_key public_key tos body tmp
  private_key="$(wg genkey)"
  public_key="$(printf '%s' "$private_key" | wg pubkey)"
  tos="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  tmp="/tmp/warp-register.$$.json"

  printf '%s\n' "$private_key" > "$PRIVATE_KEY_FILE"
  chmod 600 "$PRIVATE_KEY_FILE"

  body="$(python3 - "$public_key" "$tos" <<'PY'
import json, sys
pub, tos = sys.argv[1], sys.argv[2]
print(json.dumps({
  'key': pub,
  'install_id': '',
  'fcm_token': '',
  'tos': tos,
  'type': 'Android',
  'model': 'PC',
  'locale': 'en_US'
}))
PY
)"

  curl -fsSL -X POST 'https://api.cloudflareclient.com/v0a2158/reg' \
    -H 'Content-Type: application/json; charset=UTF-8' \
    -H 'User-Agent: okhttp/3.12.1' \
    -H 'CF-Client-Version: a-6.11-2223' \
    --data "$body" > "$tmp"

  python3 - "$tmp" <<'PY'
import json, sys
p=sys.argv[1]
data=json.load(open(p))
required=['id','token','config']
missing=[k for k in required if k not in data]
if missing:
    raise SystemExit('bad response, missing: '+','.join(missing))
PY

  mv "$tmp" "$ACCOUNT_JSON"
  chmod 600 "$ACCOUNT_JSON"
  ok "WARP-аккаунт зарегистрирован."
}

json_get_config() {
  python3 - "$ACCOUNT_JSON" "$PRIVATE_KEY_FILE" <<'PY'
import json, sys
account_path, key_path = sys.argv[1], sys.argv[2]
a=json.load(open(account_path))
private=open(key_path).read().strip()
c=a.get('config', {})
iface=c.get('interface', {})
addresses=iface.get('addresses', {})
peers=c.get('peers', [{}])
peer=peers[0] if peers else {}
endpoint=peer.get('endpoint', {}).get('host') or 'engage.cloudflareclient.com:2408'
print('PRIVATE_KEY='+private)
print('ADDRESS_V4='+addresses.get('v4','172.16.0.2'))
print('ADDRESS_V6='+addresses.get('v6','2606:4700:110:0000:0000:0000:0000:0002'))
print('PEER_PUBLIC_KEY='+peer.get('public_key','bmXOC+F1QSPGQ2ObwTOu6NWKSLW89kykyGw4RrHkGOU='))
print('ENDPOINT='+endpoint)
PY
}

write_configs() {
  log "Создаю warp.conf и proxy.conf..."
  local cfg private address_v4 address_v6 peer_public endpoint
  cfg="$(json_get_config)"
  private="$(echo "$cfg" | awk -F= '/^PRIVATE_KEY=/{print substr($0,index($0,"=")+1)}')"
  address_v4="$(echo "$cfg" | awk -F= '/^ADDRESS_V4=/{print substr($0,index($0,"=")+1)}')"
  address_v6="$(echo "$cfg" | awk -F= '/^ADDRESS_V6=/{print substr($0,index($0,"=")+1)}')"
  peer_public="$(echo "$cfg" | awk -F= '/^PEER_PUBLIC_KEY=/{print substr($0,index($0,"=")+1)}')"
  endpoint="$(echo "$cfg" | awk -F= '/^ENDPOINT=/{print substr($0,index($0,"=")+1)}')"

  cat > "$WARP_CONF" <<EOF
[Interface]
PrivateKey = $private
Address = $address_v4/32
Address = $address_v6/128
DNS = 1.1.1.1
MTU = 1280

[Peer]
PublicKey = $peer_public
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $endpoint
PersistentKeepalive = 25
EOF
  chmod 600 "$WARP_CONF"

  cat > "$PROXY_CONF" <<EOF
[Interface]
PrivateKey = $private
Address = $address_v4/32
Address = $address_v6/128
DNS = 1.1.1.1
MTU = 1280

[Peer]
PublicKey = $peer_public
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $endpoint
PersistentKeepalive = 25

[Socks5]
BindAddress = $SOCKS_HOST:$SOCKS_PORT
EOF
  chmod 600 "$PROXY_CONF"
  ok "Конфиги созданы. Первичный endpoint: $endpoint"
}

set_endpoint() {
  local ep="$1"
  sed -i "s#^Endpoint[[:space:]]*=.*#Endpoint = $ep#I" "$WARP_CONF"
  sed -i "s#^Endpoint[[:space:]]*=.*#Endpoint = $ep#I" "$PROXY_CONF"
}

create_service() {
  local bin
  bin="$(find_wireproxy_bin)"
  log "Создаю systemd service для wireproxy..."
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
  ok "wireproxy.service создан."
}

ensure_service_exists() {
  if [[ -f "$SERVICE_FILE" ]] || systemctl list-unit-files 2>/dev/null | grep -q '^wireproxy\.service'; then
    return 0
  fi
  if find_wireproxy_bin >/dev/null 2>&1 && [[ -f "$PROXY_CONF" ]]; then
    create_service
    return 0
  fi
  return 1
}

restart_wireproxy() {
  ensure_service_exists || {
    err "wireproxy.service отсутствует, а $PROXY_CONF или бинарник wireproxy не найден."
    exit 1
  }
  systemctl restart wireproxy
  sleep 2
}

check_port() {
  if ss -lntup 2>/dev/null | grep -q "$SOCKS_HOST:$SOCKS_PORT"; then
    ok "SOCKS5 слушает $SOCKS_HOST:$SOCKS_PORT"
  else
    warn "SOCKS5 порт пока не виден. Статус wireproxy:"
    systemctl status wireproxy --no-pager -l | head -80 || true
  fi
}

get_current_endpoint() {
  grep -i '^Endpoint' "$PROXY_CONF" 2>/dev/null | head -n1 | awk -F= '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}'
}

quick_warp_check() {
  local trace endpoint
  trace="$(curl -m 8 -s -x "socks5h://$SOCKS_HOST:$SOCKS_PORT" "$TEST_URL" | grep -E 'ip=|colo=|loc=|warp=' || true)"
  if echo "$trace" | grep -q '^warp=on'; then
    BEST_TRACE="$trace"
    endpoint="$(get_current_endpoint || true)"
    [[ -n "$endpoint" ]] && remember_good_endpoint "$endpoint" "0" "quick" "quick"
    return 0
  fi
  BEST_TRACE="$trace"
  return 1
}

remember_good_endpoint() {
  local ep="${1:-}" time="${2:-0}" colo="${3:-unknown}" loc="${4:-unknown}" ts
  [[ -z "$ep" ]] && return 0
  mkdir -p "$WG_DIR"
  ts="$(date +%s)"
  touch "$GOOD_ENDPOINTS_FILE" "$BAD_ENDPOINTS_FILE"
  awk -v ep="$ep" -F'\t' '$1 != ep {print}' "$GOOD_ENDPOINTS_FILE" > "${GOOD_ENDPOINTS_FILE}.tmp" 2>/dev/null || true
  mv "${GOOD_ENDPOINTS_FILE}.tmp" "$GOOD_ENDPOINTS_FILE" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\t%s\n' "$ep" "$time" "$colo" "$loc" "$ts" >> "$GOOD_ENDPOINTS_FILE"
  sort -t $'\t' -k2,2n "$GOOD_ENDPOINTS_FILE" | head -n 30 > "${GOOD_ENDPOINTS_FILE}.tmp" || true
  mv "${GOOD_ENDPOINTS_FILE}.tmp" "$GOOD_ENDPOINTS_FILE" 2>/dev/null || true
  awk -v ep="$ep" -F'\t' '$1 != ep {print}' "$BAD_ENDPOINTS_FILE" > "${BAD_ENDPOINTS_FILE}.tmp" 2>/dev/null || true
  mv "${BAD_ENDPOINTS_FILE}.tmp" "$BAD_ENDPOINTS_FILE" 2>/dev/null || true
}

remember_bad_endpoint() {
  local ep="${1:-}" ts count
  [[ -z "$ep" ]] && return 0
  mkdir -p "$WG_DIR"
  touch "$BAD_ENDPOINTS_FILE"
  ts="$(date +%s)"
  count="$(awk -v ep="$ep" -F'\t' '$1 == ep {print $2}' "$BAD_ENDPOINTS_FILE" 2>/dev/null | tail -n1)"
  count="${count:-0}"
  count=$((count + 1))
  awk -v ep="$ep" -F'\t' '$1 != ep {print}' "$BAD_ENDPOINTS_FILE" > "${BAD_ENDPOINTS_FILE}.tmp" 2>/dev/null || true
  mv "${BAD_ENDPOINTS_FILE}.tmp" "$BAD_ENDPOINTS_FILE" 2>/dev/null || true
  printf '%s\t%s\t%s\n' "$ep" "$count" "$ts" >> "$BAD_ENDPOINTS_FILE"
  tail -n 200 "$BAD_ENDPOINTS_FILE" > "${BAD_ENDPOINTS_FILE}.tmp" || true
  mv "${BAD_ENDPOINTS_FILE}.tmp" "$BAD_ENDPOINTS_FILE" 2>/dev/null || true
}

is_bad_endpoint() {
  local ep="${1:-}" now ts count age
  [[ -z "$ep" || ! -f "$BAD_ENDPOINTS_FILE" ]] && return 1
  now="$(date +%s)"
  count="$(awk -v ep="$ep" -F'\t' '$1 == ep {print $2}' "$BAD_ENDPOINTS_FILE" | tail -n1)"
  ts="$(awk -v ep="$ep" -F'\t' '$1 == ep {print $3}' "$BAD_ENDPOINTS_FILE" | tail -n1)"
  count="${count:-0}"
  ts="${ts:-0}"
  age=$((now - ts))
  [[ "$count" -ge 3 && "$age" -lt 86400 ]]
}

append_candidate() {
  local ep="${1:-}"
  [[ -z "$ep" ]] && return 0
  if is_bad_endpoint "$ep"; then
    return 0
  fi
  if ! grep -qxF "$ep" "$CANDIDATES_FILE" 2>/dev/null; then
    echo "$ep" >> "$CANDIDATES_FILE"
  fi
}

generate_endpoint_candidates() {
  : > "$CANDIDATES_FILE"
  local current_endpoint ep
  current_endpoint="$(get_current_endpoint || true)"
  [[ -n "$current_endpoint" ]] && append_candidate "$current_endpoint"

  if [[ -f "$GOOD_ENDPOINTS_FILE" ]]; then
    log "Добавляю последние хорошие endpoint'ы из кэша: $GOOD_ENDPOINTS_FILE"
    while IFS=$'\t' read -r ep _rest; do
      append_candidate "$ep"
    done < <(sort -t $'\t' -k2,2n "$GOOD_ENDPOINTS_FILE" | head -n 20)
  fi

  if [[ "$USE_CUSTOM_ENDPOINTS" == "1" ]]; then
    log "Использую пользовательский список endpoint'ов."
    for ep in "${CUSTOM_ENDPOINTS[@]}"; do
      append_candidate "$ep"
    done
    return 0
  fi

  append_candidate "engage.cloudflareclient.com:2408"
  append_candidate "162.159.192.244:1843"
  append_candidate "162.159.195.100:1010"
  append_candidate "162.159.193.10:2408"
  append_candidate "188.114.96.10:2408"
  append_candidate "188.114.97.10:2408"

  log "Генерирую до $SCAN_COUNT случайных WARP endpoint'ов из диапазонов Cloudflare..."
  log "Порты: ${WARP_PORTS[*]}"

  local made=0 attempts=0 prefix last_octet port
  while [[ "$made" -lt "$SCAN_COUNT" && "$attempts" -lt $((SCAN_COUNT * 10 + 200)) ]]; do
    attempts=$((attempts + 1))
    prefix="${WARP_PREFIXES[$((RANDOM % ${#WARP_PREFIXES[@]}))]}"
    last_octet="$((RANDOM % 256))"
    port="${WARP_PORTS[$((RANDOM % ${#WARP_PORTS[@]}))]}"
    ep="${prefix}.${last_octet}:${port}"
    if ! grep -qxF "$ep" "$CANDIDATES_FILE" 2>/dev/null && ! is_bad_endpoint "$ep"; then
      echo "$ep" >> "$CANDIDATES_FILE"
      made=$((made + 1))
    fi
  done

  ok "Кандидатов endpoint: $(wc -l < "$CANDIDATES_FILE" | tr -d ' ')"
}

test_endpoint() {
  local ep="$1"
  local trace_file="/tmp/warp_native_trace.$$"
  local rc=0

  set_endpoint "$ep"
  restart_wireproxy

  curl -m 15 -sS -x "socks5h://$SOCKS_HOST:$SOCKS_PORT" \
    -w '\n__TIME_TOTAL__=%{time_total}\n__HTTP_CODE__=%{http_code}\n' \
    "$TEST_URL" > "$trace_file" 2>/dev/null || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    printf '%s\tFAIL\tcurl_rc=%s\t-\t-\t-\t-\n' "$ep" "$rc" >> "$RESULT_FILE"
    remember_bad_endpoint "$ep"
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
    remember_good_endpoint "$ep" "$time_total" "$colo" "$loc"
    rm -f "$trace_file"
    return 0
  fi

  printf '%s\tFAIL\thttp=%s time=%s ip=%s colo=%s loc=%s warp=%s\n' "$ep" "$http_code" "$time_total" "$ip" "$colo" "$loc" "$warp" >> "$RESULT_FILE"
  remember_bad_endpoint "$ep"
  rm -f "$trace_file"
  return 1
}

select_best_endpoint() {
  generate_endpoint_candidates
  : > "$RESULT_FILE"

  log "Проверяю endpoint'ы. Кэш good/bad используется первым, затем fallback и random scan."
  local ep
  while IFS= read -r ep; do
    [[ -z "$ep" ]] && continue
    log "Проверяю $ep"
    if test_endpoint "$ep"; then
      ok "$ep работает"
    else
      warn "$ep не подошёл"
    fi
  done < "$CANDIDATES_FILE"

  echo
  echo "=== Результаты проверки ==="
  if command -v column >/dev/null 2>&1; then
    column -t -s $'\t' "$RESULT_FILE" || cat "$RESULT_FILE"
  else
    cat "$RESULT_FILE"
  fi
  echo

  local best_line
  best_line="$(awk -F'\t' '$2=="OK"{print $0}' "$RESULT_FILE" | sort -t $'\t' -k3,3n | head -n1 || true)"
  if [[ -z "$best_line" ]]; then
    err "Не найден endpoint с warp=on. Попробуй --scan-count 150 или --endpoints от внешнего сканера."
    exit 1
  fi

  BEST_ENDPOINT="$(printf '%s' "$best_line" | awk -F'\t' '{print $1}')"
  BEST_TIME="$(printf '%s' "$best_line" | awk -F'\t' '{print $3}')"
  BEST_COLO="$(printf '%s' "$best_line" | awk -F'\t' '{print $5}')"
  BEST_LOC="$(printf '%s' "$best_line" | awk -F'\t' '{print $6}')"
  set_endpoint "$BEST_ENDPOINT"
  restart_wireproxy
  remember_good_endpoint "$BEST_ENDPOINT" "$BEST_TIME" "$BEST_COLO" "$BEST_LOC"
  ok "Выбран endpoint: $BEST_ENDPOINT time_total=$BEST_TIME colo=$BEST_COLO loc=$BEST_LOC"
}

final_check() {
  log "Финальная проверка WARP..."
  BEST_TRACE="$(curl -m 15 -s -x "socks5h://$SOCKS_HOST:$SOCKS_PORT" "$TEST_URL" | grep -E 'ip=|colo=|loc=|warp=' || true)"
  echo "$BEST_TRACE"
  if ! echo "$BEST_TRACE" | grep -q '^warp=on'; then
    err "Финальная проверка не показала warp=on."
    systemctl status wireproxy --no-pager -l | head -80 || true
    exit 1
  fi
  ok "WARP работает: warp=on"
}

run_check_and_repair() {
  log "Режим проверки: проверяю текущий WARP без переустановки."
  if [[ ! -f "$PROXY_CONF" || ! -f "$WARP_CONF" ]]; then
    err "Не найдены $PROXY_CONF или $WARP_CONF. Сначала запусти обычную установку без --check."
    exit 1
  fi

  ensure_wireproxy_installed
  ensure_service_exists || create_service
  systemctl restart wireproxy || true
  sleep 2
  check_port

  if quick_warp_check; then
    ok "WARP живой, endpoint менять не нужно."
    echo "$BEST_TRACE"
    echo
    echo "Текущий endpoint: $(get_current_endpoint)"
    echo "Кэш good endpoint'ов: $GOOD_ENDPOINTS_FILE"
    exit 0
  fi

  warn "WARP не отвечает или нет warp=on. Запускаю быстрый перескан endpoint'ов..."
  backup_existing
  select_best_endpoint
  final_check
  echo
  ok "Endpoint был автоматически заменён на рабочий: $BEST_ENDPOINT"
  print_result
}

print_result() {
  local endpoint_port
  endpoint_port="${BEST_ENDPOINT##*:}"
  cat <<EOF

============================================================
ГОТОВО
============================================================

Выбранный WARP endpoint:
  $BEST_ENDPOINT

Локальный SOCKS5:
  socks5://$SOCKS_HOST:$SOCKS_PORT

Cloudflare trace:
$(echo "$BEST_TRACE" | sed 's/^/  /')

------------------------------------------------------------
3x-ui / Xray outbounds
------------------------------------------------------------

{
  "tag": "WARP-socks5",
  "protocol": "socks",
  "settings": {
    "servers": [
      {
        "address": "$SOCKS_HOST",
        "port": $SOCKS_PORT
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

Важно: в routing указывай "WARP", не "WARP-socks5".

------------------------------------------------------------
zapret4rocket
------------------------------------------------------------

Минимальный UDP-порт текущего endpoint:
  $endpoint_port

Рекомендуемая строка:
  NFQWS_PORTS_UDP=$ZAPRET_PORTS

------------------------------------------------------------
Проверки и авто-ремонт
------------------------------------------------------------

grep -i '^Endpoint' /etc/wireguard/warp.conf
systemctl status wireproxy --no-pager -l | head -60
ss -lntup | grep ':$SOCKS_PORT'
curl -m 10 -s -x socks5h://$SOCKS_HOST:$SOCKS_PORT https://www.cloudflare.com/cdn-cgi/trace | grep -E 'ip=|colo=|loc=|warp='

Проверить и при поломке автоматически заменить endpoint:
  bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warp-wireproxy-native.sh?nocache=\$(date +%s)") --check --scan-count 25

Кэш endpoint'ов:
  good: $GOOD_ENDPOINTS_FILE
  bad:  $BAD_ENDPOINTS_FILE

Бэкапы:
  /root/warp-wireproxy-native-backup/

EOF
}

cleanup() {
  rm -f "$RESULT_FILE" "$CANDIDATES_FILE" /tmp/warp_native_trace.$$ 2>/dev/null || true
}

main() {
  trap cleanup EXIT
  parse_args "$@"
  require_root
  install_deps

  if [[ "$CHECK_ONLY" == "1" ]]; then
    run_check_and_repair
    exit 0
  fi

  ensure_wireproxy_installed
  backup_existing
  register_warp_account
  write_configs
  create_service
  restart_wireproxy
  check_port
  select_best_endpoint
  final_check
  print_result
}

main "$@"
