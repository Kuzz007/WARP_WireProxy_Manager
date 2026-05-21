#!/usr/bin/env bash
# warpwp.sh
# Единый менеджер WARP + wireproxy + 3x-ui helper.
#
# Ставит короткую команду: warpwp
# В меню есть:
#   1) установить/обновить WARP + wireproxy + cron
#   2) проверить состояние
#   3) проверить и починить endpoint
#   4) обновить локальные скрипты
#   5) удалить WARP/wireproxy/cron
#   6) показать логи
#   0) выход
#
# Быстрая установка менеджера:
#   bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/test/main/warpwp.sh?nocache=$(date +%s)") --install-manager

set -Eeuo pipefail

REPO_RAW="https://raw.githubusercontent.com/Kuzz007/test/main"
NATIVE_URL="$REPO_RAW/warp-wireproxy-native.sh"
CHECK_INSTALLER_URL="$REPO_RAW/install-warp-check.sh"
MANAGER_URL="$REPO_RAW/warpwp.sh"

MANAGER_BIN="/usr/local/bin/warpwp"
NATIVE_BIN="/usr/local/bin/warp-wireproxy-native.sh"
CRON_FILE="/etc/cron.d/warp-wireproxy-check"
LOG_FILE="/var/log/warp-check.log"
DEFAULT_SCAN_COUNT="25"
DEFAULT_SCHEDULE="*/10 * * * *"

SOCKS_HOST="127.0.0.1"
SOCKS_PORT="40000"

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

pause() {
  echo
  read -rp "Нажми Enter для продолжения... " _ || true
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
  log "Устанавливаю cron-автопроверку WARP endpoint..."
  cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$DEFAULT_SCHEDULE root $NATIVE_BIN --check --scan-count $DEFAULT_SCAN_COUNT >> $LOG_FILE 2>&1
EOF
  chmod 0644 "$CRON_FILE"
  systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true
  ok "Cron включён: $CRON_FILE"
  ok "Лог: $LOG_FILE"
}

install_or_update_all() {
  need_root
  need_curl
  update_local_scripts
  log "Запускаю установку/обновление WARP + wireproxy..."
  "$NATIVE_BIN"
  install_cron_check
  ok "Установка/обновление завершены."
}

status() {
  echo "============================================================"
  echo "СОСТОЯНИЕ WARP / WIREPROXY"
  echo "============================================================"
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
}

repair_endpoint() {
  need_root
  if [[ ! -x "$NATIVE_BIN" ]]; then
    warn "Локальный native-скрипт не найден. Сначала обновляю скрипты."
    update_local_scripts
  fi
  "$NATIVE_BIN" --check --scan-count "$DEFAULT_SCAN_COUNT"
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

remove_all() {
  need_root
  echo "Это удалит WARP/wireproxy/cron/локальные скрипты."
  read -rp "Продолжить? [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES|да|Да) ;;
    *) echo "Отменено."; return 0 ;;
  esac

  log "Останавливаю сервисы..."
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

  log "Удаляю файлы..."
  rm -f /etc/systemd/system/wireproxy.service
  rm -f /etc/systemd/system/warp-svc.service
  rm -f /usr/lib/systemd/system/wireproxy.service
  rm -f /usr/lib/systemd/system/warp-svc.service
  rm -f /lib/systemd/system/wireproxy.service
  rm -f /lib/systemd/system/warp-svc.service

  rm -f /usr/bin/wireproxy /usr/local/bin/wireproxy /opt/bin/wireproxy
  rm -f /usr/bin/warp-cli /usr/local/bin/warp-cli /usr/bin/warp-svc /usr/local/bin/warp-svc
  rm -f /usr/bin/wgcf /usr/local/bin/wgcf

  rm -rf /etc/wireguard
  rm -rf /root/warp-wireproxy-backup /root/warp-wireproxy-native-backup
  rm -f /root/menu.sh /root/warp-wireproxy-auto.sh /root/warp-wireproxy-native.sh
  rm -f "$CRON_FILE" "$NATIVE_BIN" "$LOG_FILE"

  systemctl daemon-reload
  systemctl reset-failed

  ok "Удаление завершено. Команда warpwp оставлена, чтобы можно было установить заново."
}

print_commands() {
  cat <<EOF
============================================================
КОМАНДЫ
============================================================

Установить менеджер:
  bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/test/main/warpwp.sh?nocache=\$(date +%s)") --install-manager

Открыть меню:
  warpwp

Проверить и починить endpoint вручную:
  warpwp --check

Проверить состояние:
  warpwp --status

Удалить WARP/wireproxy:
  warpwp --remove

EOF
}

menu() {
  while true; do
    clear || true
    cat <<EOF
============================================================
 WARP + wireproxy manager
============================================================
 1) Установить / обновить WARP + wireproxy + cron
 2) Проверить состояние
 3) Проверить и починить endpoint
 4) Обновить локальные скрипты
 5) Удалить WARP / wireproxy / cron
 6) Показать логи
 7) Показать команды
 0) Выход
============================================================
EOF
    read -rp "Выбери пункт: " choice
    case "$choice" in
      1) install_or_update_all; pause ;;
      2) status; pause ;;
      3) repair_endpoint; pause ;;
      4) update_local_scripts; pause ;;
      5) remove_all; pause ;;
      6) show_logs; pause ;;
      7) print_commands; pause ;;
      0) exit 0 ;;
      *) echo "Неверный пункт"; sleep 1 ;;
    esac
  done
}

case "${1:-}" in
  --install-manager)
    install_manager
    ;;
  --install|--update)
    install_or_update_all
    ;;
  --status)
    status
    ;;
  --check|--repair)
    repair_endpoint
    ;;
  --logs)
    show_logs
    ;;
  --remove)
    remove_all
    ;;
  --commands)
    print_commands
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
