#!/usr/bin/env bash
# warpwp.sh
# Единый менеджер WARP + wireproxy + 3x-ui helper.

set -Eeuo pipefail

VERSION="1.1.4"
REPO_RAW="https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main"
NATIVE_URL="$REPO_RAW/warp-wireproxy-native.sh"
MANAGER_URL="$REPO_RAW/warpwp.sh"

MANAGER_BIN="/usr/local/bin/warpwp"
NATIVE_BIN="/usr/local/bin/warp-wireproxy-native.sh"
CRON_FILE="/etc/cron.d/warp-wireproxy-check"
LOG_FILE="/var/log/warp-check.log"
LOCK_FILE="/var/lock/warpwp-check.lock"
DEFAULT_SCAN_COUNT="25"
QUICK_SCAN_COUNT="15"
DEEP_SCAN_COUNT="150"
DEFAULT_SCHEDULE="*/10 * * * *"
SOCKS_HOST="127.0.0.1"
SOCKS_PORT="40000"
ZAPRET_PORTS="443,2408,1843,1010,500,1701,4500,4443,8443,8095"

log() { printf '\033[1;36m[ИНФО]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[ОК]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ВНИМАНИЕ]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ОШИБКА]\033[0m %s\n' "$*" >&2; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Запусти от root."
    exit 1
  fi
}

need_curl() {
  if command -v curl >/dev/null 2>&1; then return 0; fi
  log "curl не найден, пробую установить..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y || true
    apt-get install -y curl
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl
  else
    err "curl не найден и пакетный менеджер неизвестен."
    exit 1
  fi
}

ensure_flock() {
  if command -v flock >/dev/null 2>&1; then return 0; fi
  warn "flock не найден. Пробую установить util-linux."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y || true
    apt-get install -y util-linux || true
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y util-linux || true
  elif command -v yum >/dev/null 2>&1; then
    yum install -y util-linux || true
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache util-linux || true
  fi
}

safe_download_exec() {
  local url="$1" dest="$2" tmp
  tmp="$(mktemp)"
  curl -fsSL "${url}?nocache=$(date +%s)" -o "$tmp"
  chmod +x "$tmp"
  mv -f "$tmp" "$dest"
  chmod +x "$dest"
}

pause() {
  echo
  read -rp "Нажми Enter для продолжения... " _ || true
}

current_endpoint() {
  grep -i '^Endpoint' /etc/wireguard/warp.conf 2>/dev/null | head -n1 | awk -F= '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' || true
}

current_endpoint_port() {
  local ep
  ep="$(current_endpoint)"
  if [[ -n "$ep" && "$ep" == *:* ]]; then echo "${ep##*:}"; else echo "1843/2408/1010"; fi
}

install_manager() {
  need_root
  need_curl
  log "Устанавливаю менеджер в $MANAGER_BIN"
  safe_download_exec "$MANAGER_URL" "$MANAGER_BIN"
  ok "Готово. Теперь меню запускается командой: warpwp"
}

update_local_scripts() {
  need_root
  need_curl
  log "Обновляю локальный native-скрипт..."
  safe_download_exec "$NATIVE_URL" "$NATIVE_BIN"
  ok "Обновлён: $NATIVE_BIN"

  log "Обновляю менеджер атомарно, без перезаписи выполняемого файла..."
  safe_download_exec "$MANAGER_URL" "$MANAGER_BIN"
  ok "Обновлён: $MANAGER_BIN"
}

install_cron_check() {
  need_root
  ensure_flock
  if [[ ! -x "$NATIVE_BIN" ]]; then
    warn "Локальный native-скрипт не найден. Сначала обновляю скрипты."
    update_local_scripts
  fi

  log "Устанавливаю cron-автопроверку WARP endpoint..."
  local check_cmd
  if command -v flock >/dev/null 2>&1; then
    check_cmd="flock -n $LOCK_FILE $NATIVE_BIN --check --scan-count $DEFAULT_SCAN_COUNT"
  else
    warn "flock недоступен. Cron будет работать без lock-защиты."
    check_cmd="$NATIVE_BIN --check --scan-count $DEFAULT_SCAN_COUNT"
  fi

  cat > "$CRON_FILE" <<EOF_CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$DEFAULT_SCHEDULE root $check_cmd >> $LOG_FILE 2>&1
EOF_CRON
  chmod 0644 "$CRON_FILE"
  systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true
  ok "Cron включён: $CRON_FILE"
  ok "Лог: $LOG_FILE"
  command -v flock >/dev/null 2>&1 && ok "Lock включён: $LOCK_FILE"
}

install_or_update_all() {
  need_root
  update_local_scripts
  log "Запускаю установку/обновление WARP + wireproxy..."
  "$NATIVE_BIN"
  install_cron_check
  ok "Установка/обновление завершены."
  print_memo_short
}

status() {
  echo "============================================================"
  echo "СОСТОЯНИЕ WARP / WIREPROXY"
  echo "============================================================"
  echo "warpwp v$VERSION"
  [[ -x "$NATIVE_BIN" ]] && "$NATIVE_BIN" --version 2>/dev/null || echo "native script: not installed"
  echo
  echo "--- Endpoint ---"
  grep -i '^Endpoint' /etc/wireguard/warp.conf 2>/dev/null || echo "warp.conf не найден"
  echo
  echo "--- Service ---"
  systemctl status wireproxy --no-pager -l 2>/dev/null | head -35 || echo "wireproxy.service не найден"
  echo
  echo "--- Port $SOCKS_PORT ---"
  ss -lntup 2>/dev/null | grep ":$SOCKS_PORT" || echo "порт $SOCKS_PORT не слушается"
  echo
  echo "--- Cloudflare trace через SOCKS5 ---"
  curl -m 10 -s -x "socks5h://$SOCKS_HOST:$SOCKS_PORT" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -E 'ip=|colo=|loc=|warp=' || echo "нет ответа через SOCKS5"
  echo
  echo "--- Cron ---"
  [[ -f "$CRON_FILE" ]] && cat "$CRON_FILE" || echo "cron-файл не найден: $CRON_FILE"
  echo
  print_memo_short
}

run_scan() {
  local count="$1" label="$2"
  need_root
  [[ -x "$NATIVE_BIN" ]] || update_local_scripts
  ensure_flock
  log "$label: запускаю проверку/ремонт WARP с scan-count=$count"
  if command -v flock >/dev/null 2>&1; then
    flock -n "$LOCK_FILE" "$NATIVE_BIN" --check --scan-count "$count" || warn "Другая проверка уже выполняется или scan завершился с ошибкой."
  else
    "$NATIVE_BIN" --check --scan-count "$count"
  fi
}

repair_endpoint() { run_scan "$DEFAULT_SCAN_COUNT" "Обычный scan"; }
quick_scan() { run_scan "$QUICK_SCAN_COUNT" "Quick scan"; }
deep_scan() { run_scan "$DEEP_SCAN_COUNT" "Deep scan"; }

doctor() {
  echo "============================================================"
  echo "DOCTOR / ДИАГНОСТИКА"
  echo "============================================================"
  local ok_count=0 warn_count=0 fail_count=0
  check_ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$1"; ok_count=$((ok_count+1)); }
  check_warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$1"; warn_count=$((warn_count+1)); }
  check_fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$1"; fail_count=$((fail_count+1)); }

  [[ "${EUID}" -eq 0 ]] && check_ok "запущено от root" || check_fail "нужно запускать от root"
  for cmd in curl systemctl ss grep awk sed; do
    command -v "$cmd" >/dev/null 2>&1 && check_ok "команда $cmd найдена" || check_fail "команда $cmd не найдена"
  done
  command -v flock >/dev/null 2>&1 && check_ok "flock найден, параллельные проверки защищены" || check_warn "flock не найден"
  [[ -x "$MANAGER_BIN" ]] && check_ok "$MANAGER_BIN установлен" || check_warn "$MANAGER_BIN не найден"
  [[ -x "$NATIVE_BIN" ]] && check_ok "$NATIVE_BIN установлен" || check_warn "$NATIVE_BIN не найден"
  [[ -f /etc/wireguard/warp.conf ]] && check_ok "warp.conf найден" || check_fail "warp.conf не найден"
  [[ -f /etc/wireguard/proxy.conf ]] && check_ok "proxy.conf найден" || check_fail "proxy.conf не найден"
  [[ -f /etc/systemd/system/wireproxy.service || -f /usr/lib/systemd/system/wireproxy.service || -f /lib/systemd/system/wireproxy.service ]] && check_ok "wireproxy.service найден" || check_fail "wireproxy.service не найден"

  systemctl is-active --quiet wireproxy 2>/dev/null && check_ok "wireproxy active" || check_fail "wireproxy не active"
  ss -lntup 2>/dev/null | grep -q ":$SOCKS_PORT" && check_ok "SOCKS5 порт $SOCKS_PORT слушает" || check_fail "SOCKS5 порт $SOCKS_PORT не слушает"

  local trace
  trace="$(curl -m 10 -s -x "socks5h://$SOCKS_HOST:$SOCKS_PORT" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -E 'ip=|colo=|loc=|warp=' || true)"
  if echo "$trace" | grep -q '^warp=on'; then
    check_ok "Cloudflare trace: warp=on"
    echo "$trace"
  else
    check_fail "Cloudflare trace не дал warp=on"
    [[ -n "$trace" ]] && echo "$trace"
  fi

  if [[ -f "$CRON_FILE" ]]; then
    check_ok "cron установлен: $CRON_FILE"
    grep -q "flock -n $LOCK_FILE" "$CRON_FILE" 2>/dev/null && check_ok "cron использует flock lock" || check_warn "cron установлен, но без flock lock. Исправить: warpwp --install-cron"
  else
    check_warn "cron не установлен"
  fi
  [[ -f "$LOG_FILE" ]] && check_ok "лог существует: $LOG_FILE" || check_warn "лог пока отсутствует"

  echo
  echo "Итог: OK=$ok_count WARN=$warn_count FAIL=$fail_count"
  if [[ "$fail_count" -gt 0 || "$warn_count" -gt 0 ]]; then
    echo
    echo "Рекомендуемые действия:"
    echo "  warpwp --check"
    echo "  warpwp --install-cron"
    echo "  warpwp --install"
  fi
}

show_logs() {
  echo "============================================================"
  echo "ЛОГИ"
  echo "============================================================"
  echo "--- $LOG_FILE ---"
  tail -n 120 "$LOG_FILE" 2>/dev/null || echo "Лог пока отсутствует: $LOG_FILE"
  echo
  echo "--- journalctl -u wireproxy ---"
  journalctl -u wireproxy -n 80 --no-pager 2>/dev/null || echo "journal wireproxy недоступен"
}

remove_safe() {
  need_root
  echo "Это удалит только компоненты WARP WireProxy Manager."
  echo "Для полной очистки старых wgcf/fscarmen/warp-cli используй: warpwp --purge"
  read -rp "Продолжить безопасное удаление? [y/N]: " ans
  case "$ans" in y|Y|yes|YES|да|Да) ;; *) echo "Отменено."; return 0 ;; esac
  systemctl stop wireproxy 2>/dev/null || true
  systemctl disable wireproxy 2>/dev/null || true
  rm -f /etc/systemd/system/wireproxy.service "$CRON_FILE" "$NATIVE_BIN" "$LOG_FILE"
  rm -f /etc/wireguard/warp.conf /etc/wireguard/proxy.conf /etc/wireguard/warp-account.json /etc/wireguard/warp-private.key
  rmdir /etc/wireguard 2>/dev/null || true
  systemctl daemon-reload
  systemctl reset-failed
  ok "Безопасное удаление завершено. Команда warpwp оставлена."
}

purge_all() {
  need_root
  echo "Это жёстко удалит WARP/wireproxy/cron/wgcf/warp-cli/fscarmen-следы."
  read -rp "Продолжить PURGE? [y/N]: " ans
  case "$ans" in y|Y|yes|YES|да|Да) ;; *) echo "Отменено."; return 0 ;; esac
  systemctl stop wireproxy warp-svc wg-quick@warp wg-quick@wgcf 2>/dev/null || true
  systemctl disable wireproxy warp-svc wg-quick@warp wg-quick@wgcf 2>/dev/null || true
  pkill -f wireproxy 2>/dev/null || true
  pkill -f warp-svc 2>/dev/null || true
  pkill -f warp-cli 2>/dev/null || true
  pkill -f wgcf 2>/dev/null || true
  rm -f /etc/systemd/system/wireproxy.service /etc/systemd/system/warp-svc.service
  rm -f /usr/lib/systemd/system/wireproxy.service /usr/lib/systemd/system/warp-svc.service
  rm -f /lib/systemd/system/wireproxy.service /lib/systemd/system/warp-svc.service
  rm -f /usr/bin/wireproxy /usr/local/bin/wireproxy /opt/bin/wireproxy
  rm -f /usr/bin/warp-cli /usr/local/bin/warp-cli /usr/bin/warp-svc /usr/local/bin/warp-svc
  rm -f /usr/bin/wgcf /usr/local/bin/wgcf
  rm -rf /etc/wireguard /root/warp-wireproxy-backup /root/warp-wireproxy-native-backup
  rm -f /root/menu.sh /root/warp-wireproxy-auto.sh /root/warp-wireproxy-native.sh
  rm -f "$CRON_FILE" "$NATIVE_BIN" "$LOG_FILE"
  systemctl daemon-reload
  systemctl reset-failed
  ok "PURGE завершён. Команда warpwp оставлена."
}

print_xray() {
  cat <<EOF_XRAY
============================================================
3x-ui / Xray: WARP outbounds
============================================================

Добавь в outbounds:

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

Пример routing для OpenAI / ChatGPT:

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

Важно: routing направлять на outboundTag "WARP", не на "WARP-socks5".
EOF_XRAY
}

print_zapret() {
  local ep port
  ep="$(current_endpoint)"
  port="$(current_endpoint_port)"
  [[ -z "$ep" ]] && ep="ещё не установлен"
  cat <<EOF_ZAPRET
============================================================
zapret4rocket: WARP UDP ports
============================================================

Текущий WARP endpoint:
  $ep

Минимальный UDP-порт текущего endpoint:
  $port

Рекомендуемая строка:
  NFQWS_PORTS_UDP=$ZAPRET_PORTS

Открыть конфиг:
  nano /opt/zapret/config

Перезапустить zapret:
  /opt/zapret/init.d/sysv/zapret restart

или:
  systemctl restart zapret

Важно: локальный порт 40000 — это SOCKS5 wireproxy. Его в zapret добавлять не нужно.
EOF_ZAPRET
}

print_commands() {
  cat <<EOF_CMDS
============================================================
КОМАНДЫ
============================================================
Установить менеджер:
  bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warpwp.sh?nocache=\$(date +%s)") --install-manager

Открыть меню:
  warpwp

Основные команды:
  warpwp --install       # установить / обновить всё
  warpwp --install-cron  # переустановить только cron с flock lock
  warpwp --status        # состояние
  warpwp --doctor        # диагностика
  warpwp --check         # обычный ремонт endpoint, scan-count=$DEFAULT_SCAN_COUNT
  warpwp --quick-scan    # быстрый ремонт endpoint, scan-count=$QUICK_SCAN_COUNT
  warpwp --deep-scan     # глубокий ремонт endpoint, scan-count=$DEEP_SCAN_COUNT
  warpwp --xray          # блоки для 3x-ui/Xray
  warpwp --zapret        # строки для zapret4rocket
  warpwp --memo          # полная памятка
  warpwp --logs          # логи
  warpwp --version       # версия
  warpwp --remove        # безопасное удаление
  warpwp --purge         # жёсткая очистка
EOF_CMDS
}

print_memo_short() {
  local ep port
  ep="$(current_endpoint)"
  port="$(current_endpoint_port)"
  [[ -z "$ep" ]] && ep="ещё не установлен"
  cat <<EOF_MEMO
------------------------------------------------------------
ПАМЯТКА
SOCKS5 для 3x-ui/Xray: socks5://$SOCKS_HOST:$SOCKS_PORT
Routing в 3x-ui вести на outboundTag: WARP
Текущий WARP endpoint: $ep
Для zapret4rocket минимум UDP-порт endpoint: $port
Рекомендуемая строка zapret: NFQWS_PORTS_UDP=$ZAPRET_PORTS
Быстрый scan: warpwp --quick-scan
Обычный scan: warpwp --check
Глубокий scan: warpwp --deep-scan
Блоки Xray: warpwp --xray
Строки zapret: warpwp --zapret
Диагностика: warpwp --doctor
Логи автопроверки: tail -n 80 $LOG_FILE
------------------------------------------------------------
EOF_MEMO
}

print_memo_full() {
  print_xray
  echo
  print_zapret
  echo
  cat <<EOF_MEMO_FULL
============================================================
Полезные команды
============================================================

  warpwp --status
  warpwp --doctor
  warpwp --quick-scan
  warpwp --check
  warpwp --deep-scan
  warpwp --install-cron
  warpwp --xray
  warpwp --zapret
  warpwp --logs
  warpwp --update
  warpwp --remove
  warpwp --purge
EOF_MEMO_FULL
}

menu() {
  while true; do
    clear || true
    cat <<EOF_MENU
============================================================
 WARP + wireproxy manager v$VERSION
============================================================
 1) Установить / обновить WARP + wireproxy + cron
 2) Проверить состояние
 3) Проверить и починить endpoint
 4) Обновить локальные скрипты
 5) Безопасно удалить WARP Manager
 6) Показать логи
 7) Показать команды
 8) Показать полную памятку
 9) Doctor / расширенная диагностика
10) PURGE / жёсткая очистка WARP-следов
11) Переустановить только cron/check с flock lock
12) Показать блоки для 3x-ui / Xray
13) Показать строки для zapret4rocket
14) Quick scan endpoint
15) Deep scan endpoint
 0) Выход
============================================================
EOF_MENU
    print_memo_short
    read -rp "Выбери пункт: " choice
    case "$choice" in
      1) install_or_update_all; pause ;;
      2) status; pause ;;
      3) repair_endpoint; pause ;;
      4) update_local_scripts; pause ;;
      5) remove_safe; pause ;;
      6) show_logs; pause ;;
      7) print_commands; pause ;;
      8) print_memo_full; pause ;;
      9) doctor; pause ;;
      10) purge_all; pause ;;
      11) install_cron_check; pause ;;
      12) print_xray; pause ;;
      13) print_zapret; pause ;;
      14) quick_scan; pause ;;
      15) deep_scan; pause ;;
      0) exit 0 ;;
      *) echo "Неверный пункт"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  --install-manager) install_manager ;;
  --install) install_or_update_all ;;
  --install-cron|--cron) install_cron_check ;;
  --update|--self-update) update_local_scripts ;;
  --status) status ;;
  --doctor) doctor ;;
  --check|--repair) repair_endpoint ;;
  --quick-scan|--quick) quick_scan ;;
  --deep-scan|--deep) deep_scan ;;
  --logs) show_logs ;;
  --xray) print_xray ;;
  --zapret) print_zapret ;;
  --remove) remove_safe ;;
  --purge) purge_all ;;
  --memo) print_memo_full ;;
  --commands) print_commands ;;
  --version|-v) echo "warpwp v$VERSION" ;;
  -h|--help) print_commands ;;
  "") menu ;;
  *) err "Неизвестная опция: $1"; print_commands; exit 1 ;;
esac
