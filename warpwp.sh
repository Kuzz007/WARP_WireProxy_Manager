#!/usr/bin/env bash
# warpwp.sh
# Единый менеджер WARP + wireproxy + 3x-ui helper.

set -Eeuo pipefail

VERSION="1.1.1"
REPO_RAW="https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main"
NATIVE_URL="$REPO_RAW/warp-wireproxy-native.sh"
MANAGER_URL="$REPO_RAW/warpwp.sh"

MANAGER_BIN="/usr/local/bin/warpwp"
NATIVE_BIN="/usr/local/bin/warp-wireproxy-native.sh"
CRON_FILE="/etc/cron.d/warp-wireproxy-check"
LOG_FILE="/var/log/warp-check.log"
LOCK_FILE="/var/lock/warpwp-check.lock"
DEFAULT_SCAN_COUNT="25"
DEFAULT_SCHEDULE="*/10 * * * *"

SOCKS_HOST="127.0.0.1"
SOCKS_PORT="40000"
ZAPRET_PORTS="443,2408,1843,1010,500,1701,4500,4443,8443,8095"

log()  { printf '\033[1;36m[ИНФО]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ОК]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ВНИМАНИЕ]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ОШИБКА]\033[0m %s\n' "$*" >&2; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Запусти от root."
    exit 1
  fi
}

need_curl() {
  if command -v curl >/dev/null 2>&1; then
    return 0
  fi
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
  if command -v flock >/dev/null 2>&1; then
    return 0
  fi
  warn "flock не найден. Пробую установить util-linux для защиты cron от параллельных запусков."
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
  if [[ -n "$ep" && "$ep" == *:* ]]; then
    echo "${ep##*:}"
  else
    echo "1843/2408/1010"
  fi
}

install_manager() {
  need_root
  need_curl
  log "Устанавливаю менеджер в $MANAGER_BIN"
  curl -fsSL "${MANAGER_URL}?nocache=$(date +%s)" -o "$MANAGER_BIN"
  chmod +x "$MANAGER_BIN"
  ok "Готово. Теперь меню запускается короткой командой: warpwp"
  echo
  echo "Запустить меню:"
  echo "  warpwp"
}

update_local_scripts() {
  need_root
  need_curl
  log "Обновляю локальный native-скрипт..."
  curl -fsSL "${NATIVE_URL}?nocache=$(date +%s)" -o "$NATIVE_BIN"
  chmod +x "$NATIVE_BIN"
  ok "Обновлён: $NATIVE_BIN"

  log "Обновляю менеджер..."
  curl -fsSL "${MANAGER_URL}?nocache=$(date +%s)" -o "$MANAGER_BIN"
  chmod +x "$MANAGER_BIN"
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

  cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$DEFAULT_SCHEDULE root $check_cmd >> $LOG_FILE 2>&1
EOF
  chmod 0644 "$CRON_FILE"
  systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true
  ok "Cron включён: $CRON_FILE"
  ok "Лог: $LOG_FILE"
  if command -v flock >/dev/null 2>&1; then
    ok "Lock включён: $LOCK_FILE"
  fi
}

install_or_update_all() {
  need_root
  need_curl
  update_local_scripts
  log "Запускаю установку/обновление WARP + wireproxy..."
  "$NATIVE_BIN"
  install_cron_check
  ok "Установка/обновление завершены."
  echo
  print_memo_short
}

status() {
  echo "============================================================"
  echo "СОСТОЯНИЕ WARP / WIREPROXY"
  echo "============================================================"
  echo

  echo "--- Version ---"
  echo "warpwp v$VERSION"
  [[ -x "$NATIVE_BIN" ]] && grep -m1 '^# warp-wireproxy-native.sh' "$NATIVE_BIN" >/dev/null 2>&1 && echo "native script: installed" || echo "native script: not installed"
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
  if [[ -f "$CRON_FILE" ]]; then
    cat "$CRON_FILE"
  else
    echo "cron-файл не найден: $CRON_FILE"
  fi
  echo
  print_memo_short
}

repair_endpoint() {
  need_root
  if [[ ! -x "$NATIVE_BIN" ]]; then
    warn "Локальный native-скрипт не найден. Сначала обновляю скрипты."
    update_local_scripts
  fi
  ensure_flock
  if command -v flock >/dev/null 2>&1; then
    flock -n "$LOCK_FILE" "$NATIVE_BIN" --check --scan-count "$DEFAULT_SCAN_COUNT" || warn "Другая проверка уже выполняется или check завершился с ошибкой."
  else
    "$NATIVE_BIN" --check --scan-count "$DEFAULT_SCAN_COUNT"
  fi
}

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

  command -v flock >/dev/null 2>&1 && check_ok "flock найден, параллельные проверки защищены" || check_warn "flock не найден, cron может запускаться параллельно"
  [[ -x "$MANAGER_BIN" ]] && check_ok "$MANAGER_BIN установлен" || check_warn "$MANAGER_BIN не найден"
  [[ -x "$NATIVE_BIN" ]] && check_ok "$NATIVE_BIN установлен" || check_warn "$NATIVE_BIN не найден"

  [[ -f /etc/wireguard/warp.conf ]] && check_ok "warp.conf найден" || check_fail "warp.conf не найден"
  [[ -f /etc/wireguard/proxy.conf ]] && check_ok "proxy.conf найден" || check_fail "proxy.conf не найден"
  [[ -f /etc/systemd/system/wireproxy.service || -f /usr/lib/systemd/system/wireproxy.service || -f /lib/systemd/system/wireproxy.service ]] && check_ok "wireproxy.service найден" || check_fail "wireproxy.service не найден"

  if systemctl is-active --quiet wireproxy 2>/dev/null; then
    check_ok "wireproxy active"
  else
    check_fail "wireproxy не active"
  fi

  if ss -lntup 2>/dev/null | grep -q ":$SOCKS_PORT"; then
    check_ok "SOCKS5 порт $SOCKS_PORT слушает"
  else
    check_fail "SOCKS5 порт $SOCKS_PORT не слушает"
  fi

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
    if grep -q "flock -n $LOCK_FILE" "$CRON_FILE" 2>/dev/null; then
      check_ok "cron использует flock lock"
    else
      check_warn "cron установлен, но без flock lock. Исправить: warpwp --install-cron"
    fi
  else
    check_warn "cron не установлен"
  fi

  [[ -f "$LOG_FILE" ]] && check_ok "лог существует: $LOG_FILE" || check_warn "лог пока отсутствует"

  echo
  echo "Итог: OK=$ok_count WARN=$warn_count FAIL=$fail_count"
  if [[ "$fail_count" -gt 0 || "$warn_count" -gt 0 ]]; then
    echo
    echo "Рекомендуемые действия:"
    echo "  warpwp --check        # попробовать починить endpoint"
    echo "  warpwp --install-cron # пересоздать только cron с flock lock"
    echo "  warpwp --install      # переустановить/обновить WARP + cron"
  fi
}

show_logs() {
  echo "============================================================"
  echo "ЛОГИ"
  echo "============================================================"
  echo
  echo "--- $LOG_FILE ---"
  tail -n 120 "$LOG_FILE" 2>/dev/null || echo "Лог пока отсутствует: $LOG_FILE"
  echo
  echo "--- journalctl -u wireproxy ---"
  journalctl -u wireproxy -n 80 --no-pager 2>/dev/null || echo "journal wireproxy недоступен"
}

remove_safe() {
  need_root
  echo "Это удалит только компоненты WARP WireProxy Manager."
  echo "Для полной жёсткой очистки старых wgcf/fscarmen/warp-cli используй: warpwp --purge"
  read -rp "Продолжить безопасное удаление? [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES|да|Да) ;;
    *) echo "Отменено."; return 0 ;;
  esac

  log "Останавливаю wireproxy и cron..."
  systemctl stop wireproxy 2>/dev/null || true
  systemctl disable wireproxy 2>/dev/null || true

  rm -f /etc/systemd/system/wireproxy.service
  rm -f "$CRON_FILE" "$NATIVE_BIN" "$LOG_FILE"
  rm -f /etc/wireguard/warp.conf /etc/wireguard/proxy.conf /etc/wireguard/warp-account.json /etc/wireguard/warp-private.key
  rmdir /etc/wireguard 2>/dev/null || true

  systemctl daemon-reload
  systemctl reset-failed
  ok "Безопасное удаление завершено. Команда warpwp оставлена для повторной установки."
}

purge_all() {
  need_root
  echo "Это жёстко удалит WARP/wireproxy/cron/wgcf/warp-cli/fscarmen-следы."
  read -rp "Продолжить PURGE? [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES|да|Да) ;;
    *) echo "Отменено."; return 0 ;;
  esac

  systemctl stop wireproxy 2>/dev/null || true
  systemctl disable wireproxy 2>/dev/null || true
  systemctl stop warp-svc 2>/dev/null || true
  systemctl disable warp-svc 2>/dev/null || true
  systemctl stop wg-quick@warp 2>/dev/null || true
  systemctl disable wg-quick@warp 2>/dev/null || true
  systemctl stop wg-quick@wgcf 2>/dev/null || true
  systemctl disable wg-quick@wgcf 2>/dev/null || true

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
  ok "PURGE завершён. Команда warpwp оставлена для повторной установки."
}

print_commands() {
  cat <<EOF
============================================================
КОМАНДЫ
============================================================

Установить менеджер:
  bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warpwp.sh?nocache=\$(date +%s)") --install-manager

Открыть меню:
  warpwp

Установить / обновить всё:
  warpwp --install

Переустановить только cron с flock lock:
  warpwp --install-cron

Проверить состояние:
  warpwp --status

Расширенная диагностика:
  warpwp --doctor

Проверить и починить endpoint вручную:
  warpwp --check

Показать памятку для 3x-ui/zapret:
  warpwp --memo

Показать версию:
  warpwp --version

Безопасно удалить компоненты менеджера:
  warpwp --remove

Полная жёсткая очистка:
  warpwp --purge

EOF
}

print_memo_short() {
  local ep port
  ep="$(current_endpoint)"
  port="$(current_endpoint_port)"
  [[ -z "$ep" ]] && ep="ещё не установлен"
  cat <<EOF
------------------------------------------------------------
ПАМЯТКА
SOCKS5 для 3x-ui/Xray: socks5://$SOCKS_HOST:$SOCKS_PORT
Routing в 3x-ui вести на outboundTag: WARP
Текущий WARP endpoint: $ep
Для zapret4rocket минимум UDP-порт endpoint: $port
Рекомендуемая строка zapret: NFQWS_PORTS_UDP=$ZAPRET_PORTS
Ремонт endpoint: warpwp --check
Переустановить только cron: warpwp --install-cron
Диагностика: warpwp --doctor
Логи автопроверки: tail -n 80 $LOG_FILE
------------------------------------------------------------
EOF
}

print_memo_full() {
  local ep port
  ep="$(current_endpoint)"
  port="$(current_endpoint_port)"
  [[ -z "$ep" ]] && ep="ещё не установлен"
  cat <<EOF
============================================================
ПАМЯТКА ДЛЯ 3x-ui / Xray / zapret4rocket
============================================================

1) Локальный SOCKS5 WARP

  socks5://$SOCKS_HOST:$SOCKS_PORT

Проверка:

  curl -m 10 -s -x socks5h://$SOCKS_HOST:$SOCKS_PORT https://www.cloudflare.com/cdn-cgi/trace | grep -E 'ip=|colo=|loc=|warp='

Хороший результат:

  warp=on

------------------------------------------------------------
2) 3x-ui / Xray outbounds
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

Важно: routing правила направлять на outboundTag "WARP", не на "WARP-socks5".

------------------------------------------------------------
3) zapret4rocket
------------------------------------------------------------

Текущий endpoint:

  $ep

Минимальный UDP-порт текущего endpoint:

  $port

Рекомендуемая строка:

  NFQWS_PORTS_UDP=$ZAPRET_PORTS

------------------------------------------------------------
4) Полезные команды
------------------------------------------------------------

  warpwp --status        # состояние
  warpwp --doctor        # расширенная диагностика
  warpwp --check         # проверить и починить endpoint
  warpwp --install-cron  # пересоздать только cron с flock lock
  warpwp --logs          # логи
  warpwp --update        # обновить скрипты
  warpwp --remove        # безопасно удалить
  warpwp --purge         # жёсткая очистка

EOF
}

menu() {
  while true; do
    clear || true
    cat <<EOF
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
 8) Показать памятку для 3x-ui / zapret
 9) Doctor / расширенная диагностика
10) PURGE / жёсткая очистка WARP-следов
11) Переустановить только cron/check с flock lock
 0) Выход
============================================================
EOF
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
      0) exit 0 ;;
      *) echo "Неверный пункт"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  --install-manager)
    install_manager
    ;;
  --install)
    install_or_update_all
    ;;
  --install-cron|--cron)
    install_cron_check
    ;;
  --update|--self-update)
    update_local_scripts
    ;;
  --status)
    status
    ;;
  --doctor)
    doctor
    ;;
  --check|--repair)
    repair_endpoint
    ;;
  --logs)
    show_logs
    ;;
  --remove)
    remove_safe
    ;;
  --purge)
    purge_all
    ;;
  --memo)
    print_memo_full
    ;;
  --commands)
    print_commands
    ;;
  --version|-v)
    echo "warpwp v$VERSION"
    ;;
  -h|--help)
    print_commands
    ;;
  "")
    menu
    ;;
  *)
    err "Неизвестная опция: $1"
    print_commands
    exit 1
    ;;
esac
