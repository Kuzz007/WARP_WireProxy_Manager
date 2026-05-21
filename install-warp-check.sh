#!/usr/bin/env bash
# install-warp-check.sh
# Устанавливает локальную копию warp-wireproxy-native.sh и добавляет cron-задачу
# для проверки WARP и автоматической замены endpoint при поломке.

set -Eeuo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/Kuzz007/test/main/warp-wireproxy-native.sh"
LOCAL_SCRIPT="/usr/local/bin/warp-wireproxy-native.sh"
CRON_FILE="/etc/cron.d/warp-wireproxy-check"
LOG_FILE="/var/log/warp-check.log"
SCAN_COUNT="25"
CRON_SCHEDULE="*/10 * * * *"

log()  { printf '\033[1;36m[ИНФО]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ОК]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ОШИБКА]\033[0m %s\n' "$*" >&2; }

usage() {
  cat <<EOF
Использование:
  bash $0 [опции]

Опции:
  --scan-count <число>      Сколько endpoint'ов проверять при поломке. По умолчанию: 25
  --schedule "cron"         Расписание cron. По умолчанию: */10 * * * *
  --remove                  Удалить cron-задачу, локальный скрипт не удалять
  -h, --help                Показать справку

Примеры:
  bash $0
  bash $0 --scan-count 40
  bash $0 --schedule "*/5 * * * *"
  bash $0 --remove
EOF
}

REMOVE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-count)
      SCAN_COUNT="${2:-}"
      shift 2
      ;;
    --schedule)
      CRON_SCHEDULE="${2:-}"
      shift 2
      ;;
    --remove)
      REMOVE="1"
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

if [[ "${EUID}" -ne 0 ]]; then
  err "Запусти от root."
  exit 1
fi

if [[ "$REMOVE" == "1" ]]; then
  rm -f "$CRON_FILE"
  ok "Cron-задача удалена: $CRON_FILE"
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
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
fi

log "Скачиваю локальную копию warp-wireproxy-native.sh..."
curl -fsSL "${SCRIPT_URL}?nocache=$(date +%s)" -o "$LOCAL_SCRIPT"
chmod +x "$LOCAL_SCRIPT"
ok "Скрипт установлен: $LOCAL_SCRIPT"

log "Создаю cron-задачу: $CRON_FILE"
cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$CRON_SCHEDULE root $LOCAL_SCRIPT --check --scan-count $SCAN_COUNT >> $LOG_FILE 2>&1
EOF
chmod 0644 "$CRON_FILE"

# Ubuntu/Debian обычно подхватывает /etc/cron.d автоматически, но перезапуск не повредит.
systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true

ok "Автопроверка WARP установлена."
echo
echo "Локальный скрипт:"
echo "  $LOCAL_SCRIPT"
echo
echo "Cron-файл:"
echo "  $CRON_FILE"
echo
echo "Расписание:"
echo "  $CRON_SCHEDULE"
echo
echo "Лог:"
echo "  $LOG_FILE"
echo
echo "Проверить вручную:"
echo "  $LOCAL_SCRIPT --check --scan-count $SCAN_COUNT"
echo
echo "Посмотреть последние логи:"
echo "  tail -n 80 $LOG_FILE"
echo
echo "Удалить cron-задачу:"
echo "  bash <(curl -fsSL https://raw.githubusercontent.com/Kuzz007/test/main/install-warp-check.sh) --remove"
