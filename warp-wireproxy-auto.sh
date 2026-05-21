#!/usr/bin/env bash
# warp-wireproxy-auto.sh
# Автоустановщик Cloudflare WARP через wireproxy.
#
# Что делает:
#   - ставит зависимости;
#   - ставит WARP WireProxy через fscarmen/warp, если его ещё нет;
#   - создаёт wireproxy.service, если бинарник/конфиги есть, а systemd unit отсутствует;
#   - настраивает локальный SOCKS5 127.0.0.1:40000;
#   - сам генерирует и сканирует WARP endpoint'ы из диапазонов Cloudflare;
#   - выбирает самый быстрый endpoint, где Cloudflare trace показывает warp=on;
#   - в конце выводит готовые блоки для 3x-ui/Xray и zapret4rocket.
#
# Запуск:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Kuzz007/test/main/warp-wireproxy-auto.sh)
#
# Примеры:
#   bash warp-wireproxy-auto.sh
#   bash warp-wireproxy-auto.sh --scan-count 80
#   bash warp-wireproxy-auto.sh --ports "2408,1843,1010,500,1701,4500"
#   bash warp-wireproxy-auto.sh --endpoints "162.159.192.244:1843 162.159.195.100:1010"

set -Eeuo pipefail

SOCKS_PORT="40000"
SOCKS_HOST="127.0.0.1"
INSTALL_WARP="1"
SCAN_COUNT="40"
USE_CUSTOM_ENDPOINTS="0"

WARP_CONF="/etc/wireguard/warp.conf"
PROXY_CONF="/etc/wireguard/proxy.conf"
SERVICE_FILE="/etc/systemd/system/wireproxy.service"

FSCARMEN_MENU_URL="https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh"
TEST_URL="https://www.cloudflare.com/cdn-cgi/trace"
RESULT_FILE="/tmp/warp_endpoint_results.$$"
CANDIDATES_FILE="/tmp/warp_endpoint_candidates.$$"

BEST_ENDPOINT=""
BEST_TIME=""
BEST_TRACE=""
BEST_COLO=""
BEST_LOC=""

ZAPRET_PORTS="443,2408,1843,1010,500,1701,4500,4443,8443,8095"

# Диапазоны Cloudflare, которые часто используются WARP endpoint'ами.
# Скрипт НЕ привязан к конкретным IP: он генерирует кандидатов из этих диапазонов.
WARP_PREFIXES=(
  "162.159.192"
  "162.159.193"
  "162.159.194"
  "162.159.195"
  "188.114.96"
  "188.114.97"
  "188.114.98"
  "188.114.99"
)

# Популярные UDP-порты WARP/WireGuard/MASQUE/fallback.
WARP_PORTS=(2408 1843 1010 500 1701 4500 443 4443 8443 8095)

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
  --port <порт>             Локальный SOCKS5-порт wireproxy. По умолчанию: 40000
  --host <хост>             Адрес bind для SOCKS5. По умолчанию: 127.0.0.1
  --scan-count <число>      Сколько случайных endpoint'ов проверить. По умолчанию: 40
  --ports "список"          Порты для сканирования, через пробел или запятую
  --endpoints "список"      Проверить конкретные endpoint'ы вместо автосканирования
  --no-install              Не запускать установщик fscarmen, если wireproxy не найден
  -h, --help                Показать справку

Примеры:
  bash $0
  bash $0 --scan-count 80
  bash $0 --ports "2408,1843,1010,500,1701,4500"
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
      --no-install)
        INSTALL_WARP="0"
        shift
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
    err "Запусти скрипт от root."
    exit 1
  fi
}

install_deps_apt() {
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl wget ca-certificates grep sed gawk coreutils iproute2 systemd

  if ! command -v awk >/dev/null 2>&1 && command -v gawk >/dev/null 2>&1; then
    ln -sf "$(command -v gawk)" /usr/local/bin/awk
  fi
}

install_deps_dnf() { dnf install -y curl wget ca-certificates grep sed gawk coreutils iproute systemd; }
install_deps_yum() { yum install -y curl wget ca-certificates grep sed gawk coreutils iproute systemd; }
install_deps_apk() { apk add --no-cache curl wget ca-certificates grep sed gawk coreutils iproute2; }

detect_os_and_install_deps() {
  log "Проверяю и устанавливаю зависимости..."
  if command -v apt-get >/dev/null 2>&1; then
    install_deps_apt
  elif command -v dnf >/dev/null 2>&1; then
    install_deps_dnf
  elif command -v yum >/dev/null 2>&1; then
    install_deps_yum
  elif command -v apk >/dev/null 2>&1; then
    install_deps_apk
  else
    warn "Неизвестный пакетный менеджер. Убедись, что есть curl wget grep sed awk ip ss systemctl."
  fi

  local missing=()
  for cmd in curl wget grep sed awk ip ss systemctl sort head cut uniq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    err "Не найдены обязательные команды: ${missing[*]}"
    exit 1
  fi
  ok "Зависимости готовы."
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
    ok "wireproxy.service уже есть."
    return 0
  fi

  if ! bin="$(find_wireproxy_bin)"; then
    warn "Бинарник wireproxy не найден, unit пока создать нельзя."
    return 1
  fi

  if [[ ! -f "$PROXY_CONF" ]]; then
    warn "$PROXY_CONF не найден, unit пока создать нельзя."
    return 1
  fi

  log "Бинарник и конфиг wireproxy есть, но systemd unit отсутствует. Создаю $SERVICE_FILE"

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
  ok "Создан и включён wireproxy.service."
}

install_wireproxy_if_needed() {
  if wireproxy_install_exists; then
    ok "wireproxy и конфиги уже есть."
    create_wireproxy_service_if_missing || true
    return 0
  fi

  if [[ "$INSTALL_WARP" != "1" ]]; then
    err "wireproxy/конфиги не найдены, а указан --no-install."
    err "Нужны: бинарник wireproxy, $WARP_CONF и $PROXY_CONF"
    exit 1
  fi

  log "wireproxy или конфиги отсутствуют. Запускаю установщик fscarmen WARP WireProxy..."
  warn "Внешний установщик может задать вопросы в зависимости от системы."

  cd /root
  wget -N "$FSCARMEN_MENU_URL" -O /root/menu.sh

  bash /root/menu.sh w || {
    err "Установщик fscarmen завершился с ошибкой."
    err "Можно попробовать вручную: wget -N $FSCARMEN_MENU_URL -O /root/menu.sh && bash /root/menu.sh w"
    exit 1
  }

  if ! wireproxy_install_exists; then
    err "После установки не найдены бинарник wireproxy или конфиги."
    err "Проверь: command -v wireproxy && ls -la /etc/wireguard/"
    exit 1
  fi

  create_wireproxy_service_if_missing || true
  ok "WireProxy готов."
}

backup_configs() {
  mkdir -p /root/warp-wireproxy-backup
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  [[ -f "$WARP_CONF" ]] && cp -a "$WARP_CONF" "/root/warp-wireproxy-backup/warp.conf.$ts.bak"
  [[ -f "$PROXY_CONF" ]] && cp -a "$PROXY_CONF" "/root/warp-wireproxy-backup/proxy.conf.$ts.bak"
  [[ -f "$SERVICE_FILE" ]] && cp -a "$SERVICE_FILE" "/root/warp-wireproxy-backup/wireproxy.service.$ts.bak"
  ok "Бэкапы сохранены в /root/warp-wireproxy-backup/"
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
  log "Настраиваю SOCKS5 wireproxy на ${SOCKS_HOST}:${SOCKS_PORT}..."

  if [[ ! -f "$PROXY_CONF" ]]; then
    err "Не найден $PROXY_CONF"
    exit 1
  fi

  if grep -q '^\[Socks5\]' "$PROXY_CONF"; then
    if awk '/^\[Socks5\]/{insec=1; next} /^\[/{insec=0} insec && /^[[:space:]]*BindAddress[[:space:]]*=/{found=1} END{exit !found}' "$PROXY_CONF"; then
      awk -v bind="${SOCKS_HOST}:${SOCKS_PORT}" '
        BEGIN{insec=0}
        /^\[Socks5\]/{insec=1; print; next}
        /^\[/{insec=0; print; next}
        insec && /^[[:space:]]*BindAddress[[:space:]]*=/{print "BindAddress = " bind; next}
        {print}
      ' "$PROXY_CONF" > "${PROXY_CONF}.tmp"
      mv "${PROXY_CONF}.tmp" "$PROXY_CONF"
    else
      awk -v bind="${SOCKS_HOST}:${SOCKS_PORT}" '/^\[Socks5\]/{print; print "BindAddress = " bind; next} {print}' "$PROXY_CONF" > "${PROXY_CONF}.tmp"
      mv "${PROXY_CONF}.tmp" "$PROXY_CONF"
    fi
  else
    cat >> "$PROXY_CONF" <<EOF

[Socks5]
BindAddress = ${SOCKS_HOST}:${SOCKS_PORT}
EOF
  fi

  ok "SOCKS5 bind установлен: ${SOCKS_HOST}:${SOCKS_PORT}"
}

restart_wireproxy() {
  create_wireproxy_service_if_missing || true

  if wireproxy_unit_exists; then
    systemctl daemon-reload || true
    systemctl enable wireproxy >/dev/null 2>&1 || true
    systemctl restart wireproxy
    sleep 2
  else
    err "wireproxy.service не найден и не был создан."
    err "Диагностика: command -v wireproxy ; ls -la /etc/wireguard/"
    exit 1
  fi
}

check_port() {
  if ss -lntup 2>/dev/null | grep -q "${SOCKS_HOST}:${SOCKS_PORT}"; then
    ok "SOCKS5 слушает ${SOCKS_HOST}:${SOCKS_PORT}"
  else
    warn "Порт SOCKS5 не виден через ss. Текущие слушатели:"
    ss -lntup 2>/dev/null | grep -E 'wireproxy|40000|1080' || true
    warn "Статус wireproxy:"
    systemctl status wireproxy --no-pager -l | head -80 || true
  fi
}

generate_endpoint_candidates() {
  : > "$CANDIDATES_FILE"

  if [[ "$USE_CUSTOM_ENDPOINTS" == "1" ]]; then
    log "Использую пользовательский список endpoint'ов."
    printf '%s\n' "${CUSTOM_ENDPOINTS[@]}" | awk 'NF' | sort -u > "$CANDIDATES_FILE"
    return 0
  fi

  log "Генерирую $SCAN_COUNT WARP endpoint'ов из диапазонов Cloudflare..."
  log "Диапазоны: ${WARP_PREFIXES[*]}.*"
  log "Порты: ${WARP_PORTS[*]}"

  local made=0
  local attempts=0
  while [[ "$made" -lt "$SCAN_COUNT" && "$attempts" -lt $((SCAN_COUNT * 8 + 100)) ]]; do
    attempts=$((attempts + 1))
    local prefix="${WARP_PREFIXES[$((RANDOM % ${#WARP_PREFIXES[@]}))]}"
    local last_octet="$((RANDOM % 256))"
    local port="${WARP_PORTS[$((RANDOM % ${#WARP_PORTS[@]}))]}"
    local ep="${prefix}.${last_octet}:${port}"
    if ! grep -qxF "$ep" "$CANDIDATES_FILE"; then
      echo "$ep" >> "$CANDIDATES_FILE"
      made=$((made + 1))
    fi
  done

  # Небольшой hostname fallback, не как основной список, а как запасной вариант.
  echo "engage.cloudflareclient.com:2408" >> "$CANDIDATES_FILE"
  sort -u "$CANDIDATES_FILE" -o "$CANDIDATES_FILE"

  ok "Сгенерировано endpoint'ов: $(wc -l < "$CANDIDATES_FILE" | tr -d ' ')"
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

  printf '%s\tFAIL\thttp=%s time=%s ip=%s colo=%s loc=%s warp=%s\n' "$ep" "$http_code" "$time_total" "$ip" "$colo" "$loc" "$warp" >> "$RESULT_FILE"
  rm -f "$trace_file"
  return 1
}

select_best_endpoint() {
  generate_endpoint_candidates

  log "Начинаю проверку endpoint'ов. Это может занять несколько минут..."
  : > "$RESULT_FILE"

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
  echo "=== Результаты проверки endpoint'ов ==="
  if command -v column >/dev/null 2>&1; then
    column -t -s $'\t' "$RESULT_FILE" || cat "$RESULT_FILE"
  else
    cat "$RESULT_FILE"
  fi
  echo

  local best_line
  best_line="$(awk -F'\t' '$2=="OK"{print $0}' "$RESULT_FILE" | sort -t $'\t' -k3,3n | head -n1 || true)"

  if [[ -z "$best_line" ]]; then
    err "Не найден ни один endpoint с warp=on."
    err "Попробуй увеличить сканирование: bash $0 --scan-count 120"
    err "Или укажи endpoint'ы от внешнего WARP-сканера: bash $0 --endpoints \"IP1:PORT IP2:PORT\""
    exit 1
  fi

  BEST_ENDPOINT="$(printf '%s' "$best_line" | awk -F'\t' '{print $1}')"
  BEST_TIME="$(printf '%s' "$best_line" | awk -F'\t' '{print $3}')"
  BEST_COLO="$(printf '%s' "$best_line" | awk -F'\t' '{print $5}')"
  BEST_LOC="$(printf '%s' "$best_line" | awk -F'\t' '{print $6}')"

  set_endpoint "$BEST_ENDPOINT"
  restart_wireproxy

  ok "Выбран самый быстрый endpoint: $BEST_ENDPOINT time_total=$BEST_TIME colo=$BEST_COLO loc=$BEST_LOC"
}

final_check() {
  log "Финальная проверка WARP..."
  BEST_TRACE="$(curl -m 15 -s -x "socks5h://${SOCKS_HOST}:${SOCKS_PORT}" "$TEST_URL" | grep -E 'ip=|colo=|loc=|warp=' || true)"
  echo "$BEST_TRACE"

  if ! echo "$BEST_TRACE" | grep -q '^warp=on'; then
    err "Финальная проверка не показала warp=on."
    err "Текущий endpoint:"
    grep -i '^Endpoint' "$WARP_CONF" || true
    err "Статус wireproxy:"
    systemctl status wireproxy --no-pager -l | head -80 || true
    exit 1
  fi

  ok "Финальная проверка пройдена: warp=on"
}

print_3xui_blocks() {
  local endpoint_port
  endpoint_port="${BEST_ENDPOINT##*:}"

  cat <<EOF

============================================================
ГОТОВО
============================================================

Выбранный WARP endpoint:
  $BEST_ENDPOINT

Локальный SOCKS5:
  socks5://${SOCKS_HOST}:${SOCKS_PORT}

Cloudflare trace:
$(echo "$BEST_TRACE" | sed 's/^/  /')

------------------------------------------------------------
3x-ui / Xray outbounds
------------------------------------------------------------

Добавь эти outbounds:

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

Пример правила для отправки нужных доменов через WARP:

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

Важно:
  В routing используй outboundTag "WARP", а не "WARP-socks5".

------------------------------------------------------------
zapret4rocket
------------------------------------------------------------

Минимальный UDP-порт для текущего endpoint:
  $endpoint_port

Рекомендуемая строка:
  NFQWS_PORTS_UDP=$ZAPRET_PORTS

Открыть конфиг:
  nano /opt/zapret/config

Перезапуск:
  /opt/zapret/init.d/sysv/zapret restart

или:
  systemctl restart zapret

------------------------------------------------------------
Полезные проверки
------------------------------------------------------------

grep -i '^Endpoint' /etc/wireguard/warp.conf

systemctl status wireproxy --no-pager -l | head -60

ss -lntup | grep ':${SOCKS_PORT}'

curl -m 10 -s -x socks5h://${SOCKS_HOST}:${SOCKS_PORT} https://www.cloudflare.com/cdn-cgi/trace | grep -E 'ip=|colo=|loc=|warp='

Бэкапы:
  /root/warp-wireproxy-backup/

EOF
}

cleanup() {
  rm -f "$RESULT_FILE" "$CANDIDATES_FILE" "/tmp/warp_trace.$$" 2>/dev/null || true
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
