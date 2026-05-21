# WARP WireProxy Manager

`WARP WireProxy Manager` — неинтерактивный установщик и менеджер для схемы:

```text
3x-ui / Xray → socks5://127.0.0.1:40000 → wireproxy → Cloudflare WARP → internet
```

Проект рассчитан на VPS с Linux/systemd. Цель — быстро поднять Cloudflare WARP как локальный SOCKS5 outbound для 3x-ui/Xray, автоматически подобрать рабочий WARP endpoint и поддерживать его живым через один scheduler: cron или systemd timer.

Репозиторий:

```text
https://github.com/Kuzz007/WARP_WireProxy_Manager
```

Текущая версия:

```text
warpwp v1.1.7
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

Включить timer-режим вместо cron:

```bash
warpwp --install-timer
```

При установке timer менеджер спросит интервал проверки в минутах. По умолчанию — `10` минут.

Проверить scheduler:

```bash
warpwp --scheduler-status
```

Проверить состояние:

```bash
warpwp --doctor
warpwp --status-json
```

---

## Scheduler modes

Начиная с `warpwp v1.1.7`, cron и systemd timer сделаны взаимоисключающимися, чтобы не было двух параллельных планировщиков.

Включить cron-режим:

```bash
warpwp --install-cron
```

Что делает команда:

```text
ставит /etc/cron.d/warp-wireproxy-check
отключает и удаляет systemd timer
оставляет общий flock lock
```

Включить timer-режим:

```bash
warpwp --install-timer
```

Что делает команда:

```text
спрашивает интервал проверки в минутах
создаёт warp-wireproxy-check.service
создаёт warp-wireproxy-check.timer
удаляет /etc/cron.d/warp-wireproxy-check
оставляет общий flock lock
```

Передать интервал сразу без вопроса:

```bash
warpwp --install-timer 15
```

Проверить, что активно:

```bash
warpwp --scheduler-status
```

Возможные значения:

```text
scheduler: cron
scheduler: systemd_timer
scheduler: both
scheduler: none
```

Если случайно получилось `both`, исправить можно любой из команд:

```bash
warpwp --install-cron
```

или:

```bash
warpwp --install-timer
```

---

## Основные команды

| Команда | Что делает |
|---|---|
| `warpwp` | Открыть меню |
| `warpwp --install` | Установить/обновить WARP + wireproxy + cron |
| `warpwp --install-cron` | Включить cron и отключить timer |
| `warpwp --cron` | Алиас для `--install-cron` |
| `warpwp --install-timer [минуты]` | Включить timer и отключить cron |
| `warpwp --timer [минуты]` | Алиас для `--install-timer` |
| `warpwp --timer-status` | Показать статус systemd timer |
| `warpwp --scheduler-status` | Показать активный scheduler |
| `warpwp --scheduler` | Алиас для `--scheduler-status` |
| `warpwp --remove-timer` | Удалить systemd timer |
| `warpwp --status` | Показать состояние |
| `warpwp --status-json` | Показать JSON-статус |
| `warpwp --json` | Алиас для `--status-json` |
| `warpwp --doctor` | Расширенная диагностика |
| `warpwp --check` | Обычный ремонт endpoint, `scan-count=25` |
| `warpwp --quick-scan` | Быстрый ремонт endpoint, `scan-count=15` |
| `warpwp --deep-scan` | Глубокий ремонт endpoint, `scan-count=150` |
| `warpwp --xray` | Показать блоки для 3x-ui/Xray |
| `warpwp --zapret` | Показать строки для zapret4rocket |
| `warpwp --logs` | Показать логи |
| `warpwp --memo` | Показать полную памятку |
| `warpwp --update` | Обновить локальные скрипты |
| `warpwp --version` | Показать версию менеджера |
| `warpwp --remove` | Безопасно удалить компоненты менеджера |
| `warpwp --purge` | Жёстко удалить WARP/wireproxy/wgcf/warp-cli/fscarmen-следы |

---

## Меню

```text
============================================================
 WARP + wireproxy manager v1.1.7
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
 0) Выход
============================================================
```

---

## JSON-статус

```bash
warpwp --status-json
```

JSON включает:

```text
manager_version
native_version
healthy
scheduler
service
socks5
warp
cron
timer
logs
cache
```

Пример ключевых полей:

```json
{
  "healthy": true,
  "scheduler": "systemd_timer",
  "timer": {
    "active": true,
    "interval_minutes": 10
  },
  "cron": {
    "installed": false
  }
}
```

---

## Systemd timer

Файлы timer-режима:

```text
/etc/systemd/system/warp-wireproxy-check.service
/etc/systemd/system/warp-wireproxy-check.timer
/etc/default/warp-wireproxy-check
/var/log/warp-timer-check.log
```

Проверить timer:

```bash
warpwp --timer-status
systemctl status warp-wireproxy-check.timer --no-pager -l
systemctl list-timers --all 'warp-wireproxy-check.timer'
journalctl -u warp-wireproxy-check.service -n 80 --no-pager
```

Удалить timer:

```bash
warpwp --remove-timer
```

---

## Cron

Файл cron-режима:

```text
/etc/cron.d/warp-wireproxy-check
```

Пример:

```cron
*/10 * * * * root flock -n /var/lock/warpwp-check.lock /usr/local/bin/warp-wireproxy-native.sh --check --scan-count 25 >> /var/log/warp-check.log 2>&1
```

---

## Что умеет

- Устанавливает WARP + `wireproxy` без интерактивного меню `fscarmen`.
- Сам регистрирует WARP-устройство через Cloudflare API.
- Создаёт `warp.conf`, `proxy.conf` и `wireproxy.service`.
- Поднимает локальный SOCKS5 `127.0.0.1:40000`.
- Сканирует WARP endpoint'ы Cloudflare и выбирает рабочий endpoint с `warp=on`.
- Поддерживает `quick/check/deep scan`.
- Кэширует good/bad endpoint'ы.
- Использует blacklist для плохих endpoint'ов.
- Использует общий `flock` lock для cron/timer/manual scan.
- Показывает блоки для 3x-ui/Xray.
- Показывает строки для zapret4rocket.
- Выводит JSON-статус.

---

## Режимы scan / ремонта endpoint

```bash
warpwp --quick-scan
warpwp --check
warpwp --deep-scan
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

## Файлы в репозитории

```text
warpwp.sh                  единый менеджер с меню
warp-wireproxy-native.sh   нативный установщик WARP + wireproxy
install-warp-check.sh      отдельный установщик cron-проверки
warp-wireproxy-auto.sh     старый вариант через внешний установщик
TODO.md                    список дальнейших улучшений
.github/workflows/         CI-проверки bash-скриптов
```
