# WARP WireProxy Manager

`WARP WireProxy Manager` — неинтерактивный установщик и менеджер для схемы:

```text
3x-ui / Xray → socks5://127.0.0.1:40000 → wireproxy → Cloudflare WARP → internet
```

Проект рассчитан на VPS с Linux/systemd. Цель — быстро поднять Cloudflare WARP как локальный SOCKS5 outbound для 3x-ui/Xray, автоматически подобрать рабочий WARP endpoint и поддерживать его живым через cron или systemd timer.

Репозиторий:

```text
https://github.com/Kuzz007/WARP_WireProxy_Manager
```

Текущая версия:

```text
warpwp v1.1.6
warp-wireproxy-native.sh v1.1.0
```

---

## Быстрый старт

Установить менеджер:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warpwp.sh?nocache=$(date +%s)") --install-manager
```

Если raw-кэш GitHub отдаёт старую версию, поставить через GitHub API:

```bash
curl -fsSL \
  -H "Accept: application/vnd.github.raw" \
  "https://api.github.com/repos/Kuzz007/WARP_WireProxy_Manager/contents/warpwp.sh?ref=main" \
  -o /usr/local/bin/warpwp

chmod +x /usr/local/bin/warpwp
```

Установить/обновить WARP + wireproxy + cron:

```bash
warpwp --install
```

Опционально включить systemd timer вместо/рядом с cron:

```bash
warpwp --install-timer
```

Проверить состояние:

```bash
warpwp --doctor
warpwp --status-json
```

---

## Что умеет

- Устанавливает WARP + `wireproxy` без интерактивного меню `fscarmen`.
- Сам регистрирует WARP-устройство через Cloudflare API.
- Создаёт `warp.conf`, `proxy.conf` и `wireproxy.service`.
- Поднимает локальный SOCKS5 `127.0.0.1:40000`.
- Сканирует WARP endpoint'ы Cloudflare и выбирает рабочий endpoint с `warp=on`.
- Поддерживает режимы ремонта endpoint'ов:
  - `warpwp --quick-scan` — `scan-count=15`;
  - `warpwp --check` — `scan-count=25`;
  - `warpwp --deep-scan` — `scan-count=150`.
- Кэширует endpoint'ы:
  - good: `/etc/wireguard/warp-endpoints.good`;
  - bad: `/etc/wireguard/warp-endpoints.bad`.
- Использует blacklist: endpoint с 3+ ошибками не проверяется 24 часа.
- Использует `flock`, чтобы cron/check/timer не запускались параллельно.
- Поддерживает cron-автопроверку.
- Поддерживает optional systemd timer.
- Показывает блоки для 3x-ui/Xray.
- Показывает строки для zapret4rocket.
- Выводит JSON-статус через `warpwp --status-json`.

---

## Меню

```text
============================================================
 WARP + wireproxy manager v1.1.6
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
16) Показать JSON-статус
17) Установить systemd timer
18) Статус systemd timer
19) Удалить systemd timer
 0) Выход
============================================================
```

---

## Основные команды

| Команда | Что делает |
|---|---|
| `warpwp` | Открыть меню |
| `warpwp --install` | Установить/обновить WARP + wireproxy + cron |
| `warpwp --install-cron` | Переустановить только cron с `flock` lock |
| `warpwp --cron` | Алиас для `--install-cron` |
| `warpwp --install-timer` | Установить/включить systemd timer |
| `warpwp --timer` | Алиас для `--install-timer` |
| `warpwp --timer-status` | Показать статус systemd timer |
| `warpwp --remove-timer` | Удалить systemd timer, не трогая cron |
| `warpwp --status` | Показать состояние |
| `warpwp --status-json` | Показать JSON-статус |
| `warpwp --json` | Алиас для `--status-json` |
| `warpwp --doctor` | Расширенная диагностика |
| `warpwp --check` | Обычный ремонт endpoint, `scan-count=25` |
| `warpwp --quick-scan` | Быстрый ремонт endpoint, `scan-count=15` |
| `warpwp --deep-scan` | Глубокий ремонт endpoint, `scan-count=150` |
| `warpwp --xray` | Показать блоки для 3x-ui/Xray |
| `warpwp --zapret` | Показать строки для zapret4rocket |
| `warpwp --logs` | Показать логи cron/timer и `wireproxy` |
| `warpwp --memo` | Показать полную памятку |
| `warpwp --update` | Обновить локальные скрипты |
| `warpwp --version` | Показать версию менеджера |
| `warpwp --remove` | Безопасно удалить компоненты менеджера |
| `warpwp --purge` | Жёстко удалить WARP/wireproxy/wgcf/warp-cli/fscarmen-следы |

---

## Systemd timer

Cron остаётся дефолтным вариантом после `warpwp --install`. Systemd timer можно включить отдельно:

```bash
warpwp --install-timer
```

Будут созданы:

```text
/etc/systemd/system/warp-wireproxy-check.service
/etc/systemd/system/warp-wireproxy-check.timer
/var/log/warp-timer-check.log
```

Timer запускает check каждые 10 минут:

```text
OnBootSec=2min
OnUnitActiveSec=10min
AccuracySec=30s
Persistent=true
```

Проверить timer:

```bash
warpwp --timer-status
systemctl status warp-wireproxy-check.timer --no-pager -l
systemctl list-timers --all 'warp-wireproxy-check.timer'
journalctl -u warp-wireproxy-check.service -n 80 --no-pager
```

Удалить timer, не трогая cron:

```bash
warpwp --remove-timer
```

---

## JSON-статус

```bash
warpwp --status-json
```

или:

```bash
warpwp --json
```

JSON включает:

```text
manager_version
native_version
healthy
installed
service
socks5
warp
cron
timer
logs
cache
```

`healthy=true` означает, что WARP установлен, `wireproxy` активен, SOCKS5 слушает, Cloudflare trace даёт `warp=on`, и есть хотя бы один механизм автопроверки: cron или active systemd timer.

---

## Cron-автопроверка

После `warpwp --install` или `warpwp --install-cron` создаётся:

```text
/etc/cron.d/warp-wireproxy-check
```

Пример:

```cron
*/10 * * * * root flock -n /var/lock/warpwp-check.lock /usr/local/bin/warp-wireproxy-native.sh --check --scan-count 25 >> /var/log/warp-check.log 2>&1
```

Лог:

```bash
tail -n 80 /var/log/warp-check.log
```

---

## Режимы scan / ремонта endpoint

```bash
warpwp --quick-scan
warpwp --check
warpwp --deep-scan
```

Все режимы используют lock:

```text
/var/lock/warpwp-check.lock
```

---

## Что ставится на сервер

```text
/usr/local/bin/warpwp
/usr/local/bin/warp-wireproxy-native.sh
/etc/wireguard/warp.conf
/etc/wireguard/proxy.conf
/etc/wireguard/warp-account.json
/etc/wireguard/warp-private.key
/etc/wireguard/warp-endpoints.good
/etc/wireguard/warp-endpoints.bad
/etc/systemd/system/wireproxy.service
/etc/cron.d/warp-wireproxy-check
/etc/systemd/system/warp-wireproxy-check.service
/etc/systemd/system/warp-wireproxy-check.timer
/var/log/warp-check.log
/var/log/warp-timer-check.log
/var/lock/warpwp-check.lock
```

Бэкапы:

```text
/root/warp-wireproxy-native-backup/
```

---

## 3x-ui / Xray

```bash
warpwp --xray
```

Routing вести на:

```json
"outboundTag": "WARP"
```

---

## zapret4rocket

```bash
warpwp --zapret
```

Рекомендуемая строка:

```bash
NFQWS_PORTS_UDP=443,2408,1843,1010,500,1701,4500,4443,8443,8095
```

Локальный порт `40000` — это SOCKS5 wireproxy. Его в zapret добавлять не нужно.

---

## Проверки

```bash
warpwp --doctor
warpwp --status-json
curl -m 10 -s -x socks5h://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace | grep -E 'ip=|colo=|loc=|warp='
```

Хороший результат:

```text
warp=on
```

---

## Обновление

```bash
warpwp --update
```

Через GitHub API, если raw-кэш отдаёт старую версию:

```bash
curl -fsSL \
  -H "Accept: application/vnd.github.raw" \
  "https://api.github.com/repos/Kuzz007/WARP_WireProxy_Manager/contents/warpwp.sh?ref=main" \
  -o /usr/local/bin/warpwp

chmod +x /usr/local/bin/warpwp
```

---

## Удаление

```bash
warpwp --remove
warpwp --purge
```

---

## CI

Workflow:

```text
.github/workflows/shellcheck.yml
```

Проверяет:

```text
bash -n
shellcheck --severity=warning
```

---

## Troubleshooting

Если `apt update` падает из-за Ookla/packagecloud:

```bash
grep -Rni "packagecloud.io/ookla" /etc/apt/
grep -Rli "packagecloud.io/ookla" /etc/apt/ | xargs -r sed -i '/packagecloud\.io\/ookla/s/^/# /'
apt update
```

Проверить `wireproxy`:

```bash
systemctl status wireproxy --no-pager -l | head -80
journalctl -u wireproxy -n 80 --no-pager
```

Проверить порт:

```bash
ss -lntup | grep ':40000'
```

Проверить endpoint:

```bash
grep -i '^Endpoint' /etc/wireguard/warp.conf
```

---

## Краткая схема

```text
Клиент
  ↓
3x-ui / Xray
  ↓ outboundTag: WARP
freedom outbound
  ↓ proxySettings
WARP-socks5
  ↓
127.0.0.1:40000
  ↓
wireproxy
  ↓
Cloudflare WARP endpoint
  ↓
internet
```

---

## Файлы в репозитории

```text
warpwp.sh                  единый менеджер с меню
warp-wireproxy-native.sh   нативный установщик WARP + wireproxy
install-warp-check.sh      отдельный установщик cron-проверки
warp-wireproxy-auto.sh     старый вариант через внешний установщик
TODO.md                    список дальнейших улучшений
.github/workflows/         CI-проверки bash-скриптов
```
