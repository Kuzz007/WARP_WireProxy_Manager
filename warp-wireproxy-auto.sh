#!/usr/bin/env bash
# warp-wireproxy-auto.sh
# DEPRECATED legacy wrapper.
#
# Старый вариант через внешний установщик больше не используется.
# Для установки применяй:
#   # Установи manager из подписанного release по инструкции в README.
#   warpwp --install
#
# Этот файл оставлен для обратной совместимости: он скачивает актуальный
# warp-wireproxy-native.sh из текущего репозитория и передаёт ему все аргументы.

set -Eeuo pipefail

RELEASE_TAG="${WARPWP_RELEASE_TAG:-v1.3.4}"
NATIVE_URL="https://github.com/kuzzrus/WARP_WireProxy_Manager/releases/download/$RELEASE_TAG/warp-wireproxy-native.sh"
TMP_SCRIPT=""

log()  { printf '\033[1;36m[ИНФО]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[ВНИМАНИЕ]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[ОШИБКА]\033[0m %s\n' "$*" >&2; }

usage() {
  cat <<EOF_USAGE
warp-wireproxy-auto.sh устарел.

Используй основной менеджер:
  # Установи manager из подписанного release по инструкции в README.
  warpwp --install

Для совместимости этот wrapper передаёт аргументы в warp-wireproxy-native.sh.

Примеры:
  bash $0
  bash $0 --scan-count 80
  bash $0 --check --scan-count 25
  bash $0 --ports "2408,1843,1010,500,1701,4500"
  bash $0 --endpoints "162.159.192.244:1843 162.159.195.100:1010"
EOF_USAGE
}

# shellcheck disable=SC2329 # invoked indirectly by the EXIT trap
cleanup() {
  [[ -n "$TMP_SCRIPT" ]] && rm -f "$TMP_SCRIPT" 2>/dev/null || true
}
trap cleanup EXIT

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [[ "${EUID}" -ne 0 ]]; then
  err "Запусти от root."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  err "curl не найден. Установи curl или используй warpwp --install-manager."
  exit 1
fi

warn "warp-wireproxy-auto.sh устарел. Используй warpwp --install."
log "Скачиваю native-скрипт из release $RELEASE_TAG..."
TMP_SCRIPT="$(mktemp)"
curl -fsSL "$NATIVE_URL" -o "$TMP_SCRIPT"
bash -n "$TMP_SCRIPT"
chmod 0755 "$TMP_SCRIPT"

if "$TMP_SCRIPT" "$@"; then
  native_rc=0
else
  native_rc=$?
fi
exit "$native_rc"
