#!/usr/bin/env bash
# warpwp.sh
# Единый менеджер WARP + wireproxy + 3x-ui helper.

set -Eeuo pipefail

VERSION="1.1.9"
REPO_RAW="https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main"
NATIVE_URL="$REPO_RAW/warp-wireproxy-native.sh"
MANAGER_URL="$REPO_RAW/warpwp.sh"

MANAGER_BIN="/usr/local/bin/warpwp"
NATIVE_BIN="/usr/local/bin/warp-wireproxy-native.sh"
CRON_FILE="/etc/cron.d/warp-wireproxy-check"
LOG_FILE="/var/log/warp-check.log"
LOCK_FILE="/var/lock/warpwp-check.lock"
TIMER_SERVICE_FILE="/etc/systemd/system/warp-wireproxy-check.service"
TIMER_FILE="/etc/systemd/system/warp-wireproxy-check.timer"
TIMER_LOG_FILE="/var/log/warp-timer-check.log"
TIMER_ENV_FILE="/etc/default/warp-wireproxy-check"
DEFAULT_SCAN_COUNT="25"
QUICK_SCAN_COUNT="15"
DEEP_SCAN_COUNT="150"
DEFAULT_SCHEDULE="*/10 * * * *"
DEFAULT_TIMER_MINUTES="10"
SOCKS_HOST="127.0.0.1"
SOCKS_PORT="40000"
ZAPRET_PORTS="443,2408,1843,1010,500,1701,4500,4443,8443,8095"

log() { printf '\033[1;36m[ИНФО]\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m[ОК]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ВНИМАНИЕ]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[ОШИБКА]\033[0m %s\n' "$*" >&2; }
need_root() { [[ "${EUID}" -eq 0 ]] || { err "Запусти от root."; exit 1; }; }
pause() { echo; read -rp "Нажми Enter для продолжения... " _ || true; }
json_escape() { local s="${1:-}"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; s="${s//$'\r'/}"; s="${s//$'\t'/\\t}"; printf '%s' "$s"; }
json_bool() { [[ "${1:-}" == "1" || "${1:-}" == "true" ]] && printf 'true' || printf 'false'; }
trim() { local s="$*"; s="${s#${s%%[![:space:]]*}}"; s="${s%${s##*[![:space:]]}}"; printf '%s' "$s"; }

need_curl() { command -v curl >/dev/null 2>&1 && return 0; log "curl не найден, пробую установить..."; if command -v apt-get >/dev/null 2>&1; then apt-get update -y || true; apt-get install -y curl; elif command -v dnf >/dev/null 2>&1; then dnf install -y curl; elif command -v yum >/dev/null 2>&1; then yum install -y curl; elif command -v apk >/dev/null 2>&1; then apk add --no-cache curl; else err "curl не найден и пакетный менеджер неизвестен."; exit 1; fi; }
ensure_flock() { command -v flock >/dev/null 2>&1 && return 0; warn "flock не найден. Пробую установить util-linux."; if command -v apt-get >/dev/null 2>&1; then apt-get update -y || true; apt-get install -y util-linux || true; elif command -v dnf >/dev/null 2>&1; then dnf install -y util-linux || true; elif command -v yum >/dev/null 2>&1; then yum install -y util-linux || true; elif command -v apk >/dev/null 2>&1; then apk add --no-cache util-linux || true; fi; }
safe_download_exec() { local url="$1" dest="$2" tmp; tmp="$(mktemp)"; curl -fsSL "${url}?nocache=$(date +%s)" -o "$tmp"; chmod +x "$tmp"; mv -f "$tmp" "$dest"; chmod +x "$dest"; }
current_endpoint() { grep -i '^Endpoint' /etc/wireguard/warp.conf 2>/dev/null | head -n1 | awk -F= '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' || true; }
current_endpoint_port() { local ep; ep="$(current_endpoint)"; [[ -n "$ep" && "$ep" == *:* ]] && echo "${ep##*:}" || echo "1843/2408/1010"; }
native_version() { [[ -x "$NATIVE_BIN" ]] && "$NATIVE_BIN" --version 2>/dev/null | awk '{print $2}' || true; }
cron_installed_bool() { [[ -f "$CRON_FILE" ]] && echo 1 || echo 0; }
cron_flock_bool() { grep -q "flock -n $LOCK_FILE" "$CRON_FILE" 2>/dev/null && echo 1 || echo 0; }
timer_installed_bool() { [[ -f "$TIMER_SERVICE_FILE" && -f "$TIMER_FILE" ]] && echo 1 || echo 0; }
timer_active_bool() { systemctl is-active --quiet warp-wireproxy-check.timer 2>/dev/null && echo 1 || echo 0; }
timer_enabled_bool() { systemctl is-enabled --quiet warp-wireproxy-check.timer 2>/dev/null && echo 1 || echo 0; }
get_timer_minutes() { local value=""; if [[ -f "$TIMER_ENV_FILE" ]]; then value="$(grep -E '^TIMER_MINUTES=' "$TIMER_ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '"' || true)"; fi; [[ "$value" =~ ^[0-9]+$ ]] || value="$DEFAULT_TIMER_MINUTES"; echo "$value"; }
ask_timer_minutes() { local current input; current="$(get_timer_minutes)"; if [[ -t 0 ]]; then read -rp "Интервал проверки в минутах [${current}]: " input || true; input="${input:-$current}"; else input="${1:-$current}"; fi; if ! [[ "$input" =~ ^[0-9]+$ ]] || [[ "$input" -lt 1 ]]; then warn "Некорректный интервал '$input', использую ${DEFAULT_TIMER_MINUTES} минут."; input="$DEFAULT_TIMER_MINUTES"; fi; echo "$input"; }
install_manager() { need_root; need_curl; log "Устанавливаю менеджер в $MANAGER_BIN"; safe_download_exec "$MANAGER_URL" "$MANAGER_BIN"; ok "Готово. Теперь меню запускается командой: warpwp"; }
update_local_scripts() { need_root; need_curl; log "Обновляю native-скрипт..."; safe_download_exec "$NATIVE_URL" "$NATIVE_BIN"; ok "Обновлён: $NATIVE_BIN"; log "Обновляю менеджер..."; safe_download_exec "$MANAGER_URL" "$MANAGER_BIN"; ok "Обновлён: $MANAGER_BIN"; }
remove_cron_check() { rm -f "$CRON_FILE"; systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true; }
remove_timer_check_quiet() { systemctl disable --now warp-wireproxy-check.timer 2>/dev/null || true; rm -f "$TIMER_SERVICE_FILE" "$TIMER_FILE"; systemctl daemon-reload 2>/dev/null || true; systemctl reset-failed 2>/dev/null || true; }
install_cron_check() { need_root; ensure_flock; [[ -x "$NATIVE_BIN" ]] || { warn "Локальный native-скрипт не найден. Сначала обновляю скрипты."; update_local_scripts; }; log "Переключаю scheduler на cron: systemd timer будет отключён."; remove_timer_check_quiet; local check_cmd; if command -v flock >/dev/null 2>&1; then check_cmd="flock -n $LOCK_FILE $NATIVE_BIN --check --scan-count $DEFAULT_SCAN_COUNT"; else warn "flock недоступен. Cron будет без lock-защиты."; check_cmd="$NATIVE_BIN --check --scan-count $DEFAULT_SCAN_COUNT"; fi; cat > "$CRON_FILE" <<EOF_CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$DEFAULT_SCHEDULE root $check_cmd >> $LOG_FILE 2>&1
EOF_CRON
chmod 0644 "$CRON_FILE"; systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true; ok "Cron включён: $CRON_FILE"; ok "Systemd timer отключён, чтобы не было двойного scheduler."; }
install_timer_check() { need_root; ensure_flock; [[ -x "$NATIVE_BIN" ]] || { warn "Локальный native-скрипт не найден. Сначала обновляю скрипты."; update_local_scripts; }; local minutes exec_cmd; minutes="$(ask_timer_minutes "${1:-}")"; log "Переключаю scheduler на systemd timer: cron будет отключён."; remove_cron_check; mkdir -p "$(dirname "$TIMER_ENV_FILE")"; echo "TIMER_MINUTES=\"$minutes\"" > "$TIMER_ENV_FILE"; if command -v flock >/dev/null 2>&1; then exec_cmd="/usr/bin/flock -n $LOCK_FILE $NATIVE_BIN --check --scan-count $DEFAULT_SCAN_COUNT"; else warn "flock недоступен. Timer будет без lock-защиты."; exec_cmd="$NATIVE_BIN --check --scan-count $DEFAULT_SCAN_COUNT"; fi; cat > "$TIMER_SERVICE_FILE" <<EOF_SERVICE
[Unit]
Description=WARP WireProxy endpoint health check
Wants=network-online.target
After=network-online.target wireproxy.service

[Service]
Type=oneshot
EnvironmentFile=-$TIMER_ENV_FILE
ExecStart=/bin/bash -lc '$exec_cmd >> $TIMER_LOG_FILE 2>&1'
Nice=10
EOF_SERVICE
cat > "$TIMER_FILE" <<EOF_TIMER
[Unit]
Description=Run WARP WireProxy endpoint health check every ${minutes}min

[Timer]
OnBootSec=2min
OnUnitActiveSec=${minutes}min
AccuracySec=30s
Persistent=true
Unit=warp-wireproxy-check.service

[Install]
WantedBy=timers.target
EOF_TIMER
chmod 0644 "$TIMER_SERVICE_FILE" "$TIMER_FILE" "$TIMER_ENV_FILE"; systemctl daemon-reload; systemctl enable --now warp-wireproxy-check.timer; ok "Timer включён: warp-wireproxy-check.timer, интервал: ${minutes} минут"; ok "Cron отключён, чтобы не было двойного scheduler."; }
remove_timer_check() { need_root; log "Отключаю systemd timer..."; remove_timer_check_quiet; ok "Systemd timer удалён. Cron не тронут."; }
install_or_update_all() { need_root; update_local_scripts; log "Запускаю установку/обновление WARP + wireproxy..."; "$NATIVE_BIN"; install_cron_check; ok "Установка/обновление завершены."; print_memo_short; }
scheduler_name() { local cron timer_active; cron="$(cron_installed_bool)"; timer_active="$(timer_active_bool)"; if [[ "$cron" == "1" && "$timer_active" == "1" ]]; then echo "both"; elif [[ "$cron" == "1" ]]; then echo "cron"; elif [[ "$timer_active" == "1" ]]; then echo "systemd_timer"; else echo "none"; fi; }
scheduler_status() { echo "============================================================"; echo "SCHEDULER STATUS"; echo "============================================================"; echo "scheduler: $(scheduler_name)"; echo "cron installed: $(cron_installed_bool)"; echo "timer active: $(timer_active_bool)"; echo "timer enabled: $(timer_enabled_bool)"; echo "timer interval minutes: $(get_timer_minutes)"; [[ -f "$CRON_FILE" ]] && { echo; echo "--- cron ---"; cat "$CRON_FILE"; }; [[ -f "$TIMER_FILE" ]] && { echo; echo "--- timer ---"; cat "$TIMER_FILE"; }; }
timer_status() { scheduler_status; echo; systemctl status warp-wireproxy-check.timer --no-pager -l 2>/dev/null || true; echo; systemctl list-timers --all 'warp-wireproxy-check.timer' 2>/dev/null || true; echo; tail -n 80 "$TIMER_LOG_FILE" 2>/dev/null || true; }
status() { echo "============================================================"; echo "СОСТОЯНИЕ WARP / WIREPROXY"; echo "============================================================"; echo "warpwp v$VERSION"; [[ -x "$NATIVE_BIN" ]] && "$NATIVE_BIN" --version 2>/dev/null || echo "native script: not installed"; echo; echo "--- Endpoint ---"; grep -i '^Endpoint' /etc/wireguard/warp.conf 2>/dev/null || echo "warp.conf не найден"; echo; echo "--- Service ---"; systemctl status wireproxy --no-pager -l 2>/dev/null | head -35 || echo "wireproxy.service не найден"; echo; echo "--- Port $SOCKS_PORT ---"; ss -lntup 2>/dev/null | grep ":$SOCKS_PORT" || echo "порт $SOCKS_PORT не слушается"; echo; echo "--- Cloudflare trace через SOCKS5 ---"; curl -m 10 -s -x "socks5h://$SOCKS_HOST:$SOCKS_PORT" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -E 'ip=|colo=|loc=|warp=' || echo "нет ответа через SOCKS5"; echo; scheduler_status; echo; print_memo_short; }
status_json() { local ep ep_port native_ver service_state service_active socks_listening cron_installed cron_flock log_exists manager_installed native_installed trace ip colo loc warp installed healthy timer_installed timer_active timer_enabled timer_minutes timer_log_exists scheduler; ep="$(current_endpoint)"; ep_port="$(current_endpoint_port)"; native_ver="$(native_version)"; service_state="$(systemctl is-active wireproxy 2>/dev/null || true)"; [[ "$service_state" == "active" ]] && service_active="1" || service_active="0"; ss -lntup 2>/dev/null | grep -q ":$SOCKS_PORT" && socks_listening="1" || socks_listening="0"; cron_installed="$(cron_installed_bool)"; cron_flock="$(cron_flock_bool)"; [[ -f "$LOG_FILE" ]] && log_exists="1" || log_exists="0"; [[ -x "$MANAGER_BIN" ]] && manager_installed="1" || manager_installed="0"; [[ -x "$NATIVE_BIN" ]] && native_installed="1" || native_installed="0"; [[ -f /etc/wireguard/warp.conf && -f /etc/wireguard/proxy.conf ]] && installed="1" || installed="0"; timer_installed="$(timer_installed_bool)"; timer_active="$(timer_active_bool)"; timer_enabled="$(timer_enabled_bool)"; timer_minutes="$(get_timer_minutes)"; [[ -f "$TIMER_LOG_FILE" ]] && timer_log_exists="1" || timer_log_exists="0"; scheduler="$(scheduler_name)"; trace="$(curl -m 10 -s -x "socks5h://$SOCKS_HOST:$SOCKS_PORT" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null || true)"; ip="$(echo "$trace" | awk -F= '$1=="ip"{print $2; exit}')"; colo="$(echo "$trace" | awk -F= '$1=="colo"{print $2; exit}')"; loc="$(echo "$trace" | awk -F= '$1=="loc"{print $2; exit}')"; warp="$(echo "$trace" | awk -F= '$1=="warp"{print $2; exit}')"; [[ "$installed" == "1" && "$service_active" == "1" && "$socks_listening" == "1" && "$warp" == "on" && "$scheduler" != "none" ]] && healthy="1" || healthy="0"; cat <<EOF_JSON
{
  "manager_version": "$(json_escape "$VERSION")",
  "native_version": "$(json_escape "$native_ver")",
  "healthy": $(json_bool "$healthy"),
  "scheduler": "$(json_escape "$scheduler")",
  "installed": $(json_bool "$installed"),
  "manager_installed": $(json_bool "$manager_installed"),
  "native_installed": $(json_bool "$native_installed"),
  "service": {"name": "wireproxy", "state": "$(json_escape "$service_state")", "active": $(json_bool "$service_active")},
  "socks5": {"host": "$(json_escape "$SOCKS_HOST")", "port": $SOCKS_PORT, "listening": $(json_bool "$socks_listening")},
  "warp": {"endpoint": "$(json_escape "$ep")", "endpoint_port": "$(json_escape "$ep_port")", "ip": "$(json_escape "$ip")", "colo": "$(json_escape "$colo")", "loc": "$(json_escape "$loc")", "status": "$(json_escape "$warp")", "on": $( [[ "$warp" == "on" ]] && printf 'true' || printf 'false' )},
  "cron": {"file": "$(json_escape "$CRON_FILE")", "installed": $(json_bool "$cron_installed"), "uses_flock": $(json_bool "$cron_flock"), "lock_file": "$(json_escape "$LOCK_FILE")", "schedule": "$(json_escape "$DEFAULT_SCHEDULE")"},
  "timer": {"service_file": "$(json_escape "$TIMER_SERVICE_FILE")", "timer_file": "$(json_escape "$TIMER_FILE")", "installed": $(json_bool "$timer_installed"), "enabled": $(json_bool "$timer_enabled"), "active": $(json_bool "$timer_active"), "interval_minutes": $timer_minutes, "log_file": "$(json_escape "$TIMER_LOG_FILE")", "log_exists": $(json_bool "$timer_log_exists")},
  "logs": {"cron_file": "$(json_escape "$LOG_FILE")", "cron_exists": $(json_bool "$log_exists"), "timer_file": "$(json_escape "$TIMER_LOG_FILE")", "timer_exists": $(json_bool "$timer_log_exists")},
  "cache": {"good_file": "/etc/wireguard/warp-endpoints.good", "bad_file": "/etc/wireguard/warp-endpoints.bad"}
}
EOF_JSON
}
run_scan() { local count="$1" label="$2"; need_root; [[ -x "$NATIVE_BIN" ]] || update_local_scripts; ensure_flock; log "$label: запускаю проверку/ремонт WARP с scan-count=$count"; if command -v flock >/dev/null 2>&1; then flock -n "$LOCK_FILE" "$NATIVE_BIN" --check --scan-count "$count" || warn "Другая проверка уже выполняется или scan завершился с ошибкой."; else "$NATIVE_BIN" --check --scan-count "$count"; fi; }
repair_endpoint() { run_scan "$DEFAULT_SCAN_COUNT" "Обычный scan"; }
quick_scan() { run_scan "$QUICK_SCAN_COUNT" "Quick scan"; }
deep_scan() { run_scan "$DEEP_SCAN_COUNT" "Deep scan"; }
doctor() { echo "============================================================"; echo "DOCTOR / ДИАГНОСТИКА"; echo "============================================================"; local ok_count=0 warn_count=0 fail_count=0 scheduler trace; check_ok() { printf '\033[1;32m[OK]\033[0m %s\n' "$1"; ok_count=$((ok_count+1)); }; check_warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$1"; warn_count=$((warn_count+1)); }; check_fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$1"; fail_count=$((fail_count+1)); }; [[ "${EUID}" -eq 0 ]] && check_ok "запущено от root" || check_fail "нужно запускать от root"; for cmd in curl systemctl ss grep awk sed; do command -v "$cmd" >/dev/null 2>&1 && check_ok "команда $cmd найдена" || check_fail "команда $cmd не найдена"; done; command -v flock >/dev/null 2>&1 && check_ok "flock найден" || check_warn "flock не найден"; [[ -x "$MANAGER_BIN" ]] && check_ok "$MANAGER_BIN установлен" || check_warn "$MANAGER_BIN не найден"; [[ -x "$NATIVE_BIN" ]] && check_ok "$NATIVE_BIN установлен" || check_warn "$NATIVE_BIN не найден"; [[ -f /etc/wireguard/warp.conf ]] && check_ok "warp.conf найден" || check_fail "warp.conf не найден"; [[ -f /etc/wireguard/proxy.conf ]] && check_ok "proxy.conf найден" || check_fail "proxy.conf не найден"; systemctl is-active --quiet wireproxy 2>/dev/null && check_ok "wireproxy active" || check_fail "wireproxy не active"; ss -lntup 2>/dev/null | grep -q ":$SOCKS_PORT" && check_ok "SOCKS5 порт $SOCKS_PORT слушает" || check_fail "SOCKS5 порт $SOCKS_PORT не слушает"; trace="$(curl -m 10 -s -x "socks5h://$SOCKS_HOST:$SOCKS_PORT" https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep -E 'ip=|colo=|loc=|warp=' || true)"; if echo "$trace" | grep -q '^warp=on'; then check_ok "Cloudflare trace: warp=on"; echo "$trace"; else check_fail "Cloudflare trace не дал warp=on"; [[ -n "$trace" ]] && echo "$trace"; fi; scheduler="$(scheduler_name)"; case "$scheduler" in cron) check_ok "scheduler: cron" ;; systemd_timer) check_ok "scheduler: systemd timer"; check_ok "timer interval: $(get_timer_minutes) min" ;; both) check_warn "активны оба scheduler: cron и timer. Исправить: warpwp --install-cron или warpwp --install-timer" ;; none) check_fail "scheduler не установлен" ;; esac; [[ "$scheduler" == "cron" && "$(cron_flock_bool)" == "1" ]] && check_ok "cron использует flock lock" || true; [[ -f "$LOG_FILE" || -f "$TIMER_LOG_FILE" ]] && check_ok "лог существует" || check_warn "логи пока отсутствуют"; echo; echo "Итог: OK=$ok_count WARN=$warn_count FAIL=$fail_count"; }
show_logs() { echo "--- $LOG_FILE ---"; tail -n 120 "$LOG_FILE" 2>/dev/null || true; echo; echo "--- $TIMER_LOG_FILE ---"; tail -n 80 "$TIMER_LOG_FILE" 2>/dev/null || true; echo; journalctl -u wireproxy -n 80 --no-pager 2>/dev/null || true; }
remove_safe() { need_root; echo "Это удалит компоненты WARP WireProxy Manager."; read -rp "Продолжить? [y/N]: " ans; case "$ans" in y|Y|yes|YES|да|Да) ;; *) echo "Отменено."; return 0 ;; esac; systemctl stop wireproxy 2>/dev/null || true; systemctl disable wireproxy 2>/dev/null || true; remove_timer_check_quiet; rm -f /etc/systemd/system/wireproxy.service "$CRON_FILE" "$NATIVE_BIN" "$LOG_FILE" "$TIMER_LOG_FILE" "$TIMER_ENV_FILE"; rm -f /etc/wireguard/warp.conf /etc/wireguard/proxy.conf /etc/wireguard/warp-account.json /etc/wireguard/warp-private.key; rmdir /etc/wireguard 2>/dev/null || true; systemctl daemon-reload; systemctl reset-failed; ok "Удаление завершено. Команда warpwp оставлена."; }
purge_all() { need_root; echo "Это жёстко удалит WARP/wireproxy/cron/timer/wgcf/warp-cli/fscarmen-следы."; read -rp "Продолжить PURGE? [y/N]: " ans; case "$ans" in y|Y|yes|YES|да|Да) ;; *) echo "Отменено."; return 0 ;; esac; remove_timer_check_quiet; systemctl stop wireproxy warp-svc wg-quick@warp wg-quick@wgcf 2>/dev/null || true; systemctl disable wireproxy warp-svc wg-quick@warp wg-quick@wgcf 2>/dev/null || true; pkill -f wireproxy 2>/dev/null || true; pkill -f warp-svc 2>/dev/null || true; pkill -f warp-cli 2>/dev/null || true; pkill -f wgcf 2>/dev/null || true; rm -f /etc/systemd/system/wireproxy.service /etc/systemd/system/warp-svc.service /usr/lib/systemd/system/wireproxy.service /usr/lib/systemd/system/warp-svc.service /lib/systemd/system/wireproxy.service /lib/systemd/system/warp-svc.service; rm -f /usr/bin/wireproxy /usr/local/bin/wireproxy /opt/bin/wireproxy /usr/bin/warp-cli /usr/local/bin/warp-cli /usr/bin/warp-svc /usr/local/bin/warp-svc /usr/bin/wgcf /usr/local/bin/wgcf; rm -rf /etc/wireguard /root/warp-wireproxy-backup /root/warp-wireproxy-native-backup; rm -f /root/menu.sh /root/warp-wireproxy-auto.sh /root/warp-wireproxy-native.sh "$CRON_FILE" "$NATIVE_BIN" "$LOG_FILE" "$TIMER_LOG_FILE" "$TIMER_ENV_FILE"; systemctl daemon-reload; systemctl reset-failed; ok "PURGE завершён. Команда warpwp оставлена."; }
wg_emit_json() { local source_file="$1" line section key value private_key address mtu public_key endpoint allowed_ips keepalive preshared_key workers no_kernel_tun; mtu="1420"; keepalive="0"; workers="2"; no_kernel_tun="false"; section=""; while IFS= read -r line || [[ -n "$line" ]]; do line="${line%%#*}"; line="$(trim "$line")"; [[ -z "$line" ]] && continue; case "$line" in "[Interface]") section="interface"; continue ;; "[Peer]") section="peer"; continue ;; esac; [[ "$line" == *=* ]] || continue; key="$(trim "${line%%=*}")"; value="$(trim "${line#*=}")"; key="${key,,}"; case "$section:$key" in interface:privatekey) private_key="$value" ;; interface:address) address="$value" ;; interface:mtu) mtu="$value" ;; peer:publickey) public_key="$value" ;; peer:presharedkey) preshared_key="$value" ;; peer:endpoint) endpoint="$value" ;; peer:allowedips) allowed_ips="$value" ;; peer:persistentkeepalive) keepalive="$value" ;; esac; done < "$source_file"; if [[ -z "${private_key:-}" || -z "${address:-}" || -z "${public_key:-}" || -z "${endpoint:-}" ]]; then err "Не хватает обязательных полей: PrivateKey, Address, Peer PublicKey, Endpoint."; return 1; fi; [[ -n "${allowed_ips:-}" ]] || allowed_ips="0.0.0.0/0, ::/0"; echo "============================================================"; echo "3x-ui / Xray WireGuard JSON"; echo "============================================================"; echo "Вставь этот блок в окно создания outbound на вкладке JSON."; echo; printf '{\n'; printf '  "protocol": "wireguard",\n'; printf '  "settings": {\n'; printf '    "mtu": %s,\n' "$mtu"; printf '    "secretKey": "%s",\n' "$(json_escape "$private_key")"; printf '    "address": [\n'; IFS=',' read -ra addr_arr <<< "$address"; local i item total; total="${#addr_arr[@]}"; for i in "${!addr_arr[@]}"; do item="$(trim "${addr_arr[$i]}")"; printf '      "%s"' "$(json_escape "$item")"; [[ "$i" -lt $((total-1)) ]] && printf ','; printf '\n'; done; printf '    ],\n'; printf '    "workers": %s,\n' "$workers"; printf '    "peers": [\n'; printf '      {\n'; printf '        "publicKey": "%s",\n' "$(json_escape "$public_key")"; if [[ -n "${preshared_key:-}" ]]; then printf '        "preSharedKey": "%s",\n' "$(json_escape "$preshared_key")"; fi; printf '        "allowedIPs": [\n'; IFS=',' read -ra allowed_arr <<< "$allowed_ips"; total="${#allowed_arr[@]}"; for i in "${!allowed_arr[@]}"; do item="$(trim "${allowed_arr[$i]}")"; printf '          "%s"' "$(json_escape "$item")"; [[ "$i" -lt $((total-1)) ]] && printf ','; printf '\n'; done; printf '        ],\n'; printf '        "endpoint": "%s",\n' "$(json_escape "$endpoint")"; printf '        "keepAlive": %s\n' "$keepalive"; printf '      }\n'; printf '    ],\n'; printf '    "noKernelTun": %s\n' "$no_kernel_tun"; printf '  }\n'; printf '}\n'; echo; echo "Подсказка: после создания outbound задай tag, например WG, и используй routing на outboundTag WG."; }
wg_conf_to_json() { local file="${1:-}"; if [[ -z "$file" && -t 0 ]]; then read -rp "Путь к WireGuard .conf: " file; fi; if [[ -z "$file" || ! -r "$file" ]]; then err "Файл WireGuard .conf не найден/не читается: ${file:-empty}"; echo "Пример: warpwp --wg-json /root/wg0.conf"; return 1; fi; wg_emit_json "$file"; }
wg_paste_to_json() { local tmp line got=0; tmp="$(mktemp)"; trap 'rm -f "$tmp"' RETURN; echo "Вставь WireGuard config целиком. После вставки ничего не нажимай 2 секунды — JSON появится автоматически."; echo; while true; do if [[ "$got" -eq 0 ]]; then IFS= read -r line || break; got=1; else IFS= read -r -t 2 line || break; fi; printf '%s\n' "$line" >> "$tmp"; done; if [[ ! -s "$tmp" ]]; then err "Конфиг не получен."; return 1; fi; wg_emit_json "$tmp"; }
print_xray() { cat <<EOF_XRAY
============================================================
3x-ui / Xray: WARP outbounds
============================================================

{
  "tag": "WARP-socks5",
  "protocol": "socks",
  "settings": {"servers": [{"address": "$SOCKS_HOST", "port": $SOCKS_PORT}]}
},
{
  "tag": "WARP",
  "protocol": "freedom",
  "settings": {"domainStrategy": "UseIPv4"},
  "proxySettings": {"tag": "WARP-socks5"}
}

Routing направлять на outboundTag "WARP", не на "WARP-socks5".
EOF_XRAY
}
print_zapret() { local ep port; ep="$(current_endpoint)"; port="$(current_endpoint_port)"; [[ -z "$ep" ]] && ep="ещё не установлен"; cat <<EOF_ZAPRET
============================================================
zapret4rocket: WARP UDP ports
============================================================
Текущий WARP endpoint: $ep
Минимальный UDP-порт endpoint: $port
NFQWS_PORTS_UDP=$ZAPRET_PORTS
Локальный порт 40000 — это SOCKS5 wireproxy, его в zapret добавлять не нужно.
EOF_ZAPRET
}
print_commands() { cat <<EOF_CMDS
============================================================
КОМАНДЫ
============================================================
  warpwp --install          # установить / обновить всё + cron
  warpwp --install-cron     # включить cron и отключить timer
  warpwp --install-timer    # включить timer и отключить cron, спросит интервал
  warpwp --timer-status     # статус systemd timer
  warpwp --scheduler-status # какой scheduler активен
  warpwp --remove-timer     # удалить systemd timer
  warpwp --status           # состояние
  warpwp --status-json      # JSON-статус
  warpwp --doctor           # диагностика
  warpwp --check            # scan-count=$DEFAULT_SCAN_COUNT
  warpwp --quick-scan       # scan-count=$QUICK_SCAN_COUNT
  warpwp --deep-scan        # scan-count=$DEEP_SCAN_COUNT
  warpwp --xray             # блоки для 3x-ui/Xray
  warpwp --zapret           # строки для zapret4rocket
  warpwp --wg-paste         # вставить WireGuard .conf и получить JSON для 3x-ui
  warpwp --wg-json FILE     # конвертировать WireGuard .conf из файла
  warpwp --logs             # логи
  warpwp --version          # версия
EOF_CMDS
}
print_memo_short() { local ep port; ep="$(current_endpoint)"; port="$(current_endpoint_port)"; [[ -z "$ep" ]] && ep="ещё не установлен"; cat <<EOF_MEMO
------------------------------------------------------------
ПАМЯТКА
SOCKS5: socks5://$SOCKS_HOST:$SOCKS_PORT
Endpoint: $ep
zapret UDP ports: $ZAPRET_PORTS
Scheduler: warpwp --scheduler-status
WG paste: warpwp --wg-paste
JSON: warpwp --status-json
Scan: warpwp --quick-scan / warpwp --check / warpwp --deep-scan
------------------------------------------------------------
EOF_MEMO
}
print_memo_full() { print_xray; echo; print_zapret; echo; print_commands; }
menu() { while true; do clear || true; cat <<EOF_MENU
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
11) Включить cron/check и отключить timer
12) Показать блоки для 3x-ui / Xray
13) Показать строки для zapret4rocket
14) Quick scan endpoint
15) Deep scan endpoint
16) Показать JSON-статус
17) Включить systemd timer и отключить cron
18) Статус systemd timer
19) Удалить systemd timer
20) Scheduler status
21) Вставить WireGuard .conf и получить JSON для 3x-ui
22) Конвертировать WireGuard .conf файл в JSON для 3x-ui
 0) Выход
============================================================
EOF_MENU
print_memo_short; read -rp "Выбери пункт: " choice; case "$choice" in 1) install_or_update_all; pause ;; 2) status; pause ;; 3) repair_endpoint; pause ;; 4) update_local_scripts; pause ;; 5) remove_safe; pause ;; 6) show_logs; pause ;; 7) print_commands; pause ;; 8) print_memo_full; pause ;; 9) doctor; pause ;; 10) purge_all; pause ;; 11) install_cron_check; pause ;; 12) print_xray; pause ;; 13) print_zapret; pause ;; 14) quick_scan; pause ;; 15) deep_scan; pause ;; 16) status_json; pause ;; 17) install_timer_check; pause ;; 18) timer_status; pause ;; 19) remove_timer_check; pause ;; 20) scheduler_status; pause ;; 21) wg_paste_to_json; pause ;; 22) wg_conf_to_json; pause ;; 0) exit 0 ;; *) echo "Неверный пункт"; sleep 1 ;; esac; done; }
case "${1:-}" in --install-manager) install_manager ;; --install) install_or_update_all ;; --install-cron|--cron) install_cron_check ;; --install-timer|--timer) install_timer_check "${2:-}" ;; --timer-status) timer_status ;; --scheduler-status|--scheduler) scheduler_status ;; --remove-timer) remove_timer_check ;; --update|--self-update) update_local_scripts ;; --status) status ;; --status-json|--json) status_json ;; --doctor) doctor ;; --check|--repair) repair_endpoint ;; --quick-scan|--quick) quick_scan ;; --deep-scan|--deep) deep_scan ;; --logs) show_logs ;; --xray) print_xray ;; --zapret) print_zapret ;; --wg-paste|--wg-stdin) wg_paste_to_json ;; --wg-json|--wg-convert) wg_conf_to_json "${2:-}" ;; --remove) remove_safe ;; --purge) purge_all ;; --memo) print_memo_full ;; --commands) print_commands ;; --version|-v) echo "warpwp v$VERSION" ;; -h|--help) print_commands ;; "") menu ;; *) err "Неизвестная опция: $1"; print_commands; exit 1 ;; esac
