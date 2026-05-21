# WARP WireProxy Manager

`WARP WireProxy Manager` — неинтерактивный установщик и менеджер для схемы:

```text
3x-ui / Xray → socks5://127.0.0.1:40000 → wireproxy → Cloudflare WARP → internet
```

Проект рассчитан на VPS с Linux/systemd. Цель — быстро поднять Cloudflare WARP как локальный SOCKS5 outbound для 3x-ui/Xray, автоматически подобрать рабочий WARP endpoint и поддерживать его живым через cron-проверку.

Репозиторий:

```text
https://github.com/Kuzz007/WARP_WireProxy_Manager
```

Текущая версия:

```text
warpwp v1.1.5
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

Открыть меню:

```bash
warpwp
```

Установить/обновить WARP + wireproxy + cron:

```bash
warpwp --install
```

Проверить состояние:

```bash
warpwp --doctor
```

Хороший итог:

```text
OK=19 WARN=0 FAIL=0
warp=on
wireproxy active
cron установлен
cron использует flock lock
```

---

## Что умеет

- Устанавливает WARP + `wireproxy` без интерактивного меню `fscarmen`.
- Сам регистрирует WARP-устройство через Cloudflare API.
- Создаёт `warp.conf`, `proxy.conf` и `wireproxy.service`.
- Поднимает локальный SOCKS5:

```text
127.0.0.1:40000
```

- Сканирует WARP endpoint'ы Cloudflare.
- Выбирает рабочий endpoint, где Cloudflare trace показывает `warp=on`.
- Поддерживает три режима ремонта endpoint'ов:
  - `warpwp --quick-scan` — быстрый scan, `scan-count=15`;
  - `warpwp --check` — обычный scan, `scan-count=25`;
  - `warpwp --deep-scan` — глубокий scan, `scan-count=150`.
- Кэширует хорошие endpoint'ы: `/etc/wireguard/warp-endpoints.good`.
- Кэширует плохие endpoint'ы: `/etc/wireguard/warp-endpoints.bad`.
- Использует blacklist: endpoint с 3+ ошибками не проверяется 24 часа.
- Использует `flock`, чтобы cron/check не запускались параллельно.
- Показывает готовые блоки для 3x-ui/Xray.
- Показывает готовые строки для zapret4rocket.
- Выводит машинно-читаемый JSON-статус через `warpwp --status-json`.

---

## Меню

```text
============================================================
 WARP + wireproxy manager v1.1.5
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
| `warpwp --status` | Показать состояние |
| `warpwp --status-json` | Показать JSON-статус |
| `warpwp --json` | Алиас для `--status-json` |
| `warpwp --doctor` | Расширенная диагностика |
| `warpwp --check` | Обычный ремонт endpoint, `scan-count=25` |
| `warpwp --quick-scan` | Быстрый ремонт endpoint, `scan-count=15` |
| `warpwp --quick` | Алиас для `--quick-scan` |
| `warpwp --deep-scan` | Глубокий ремонт endpoint, `scan-count=150` |
| `warpwp --deep` | Алиас для `--deep-scan` |
| `warpwp --xray` | Показать блоки для 3x-ui/Xray |
| `warpwp --zapret` | Показать строки для zapret4rocket |
| `warpwp --logs` | Показать логи cron и `wireproxy` |
| `warpwp --memo` | Показать полную памятку |
| `warpwp --update` | Обновить локальные скрипты |
| `warpwp --self-update` | То же самое, что `--update` |
| `warpwp --version` | Показать версию менеджера |
| `warpwp --remove` | Безопасно удалить компоненты менеджера |
| `warpwp --purge` | Жёстко удалить WARP/wireproxy/wgcf/warp-cli/fscarmen-следы |

---

## JSON-статус

Вывести машинно-читаемый статус:

```bash
warpwp --status-json
```

или:

```bash
warpwp --json
```

Пример структуры:

```json
{
  "manager_version": "1.1.5",
  "native_version": "1.1.0",
  "healthy": true,
  "installed": true,
  "service": {
    "name": "wireproxy",
    "state": "active",
    "active": true
  },
  "socks5": {
    "host": "127.0.0.1",
    "port": 40000,
    "listening": true
  },
  "warp": {
    "endpoint": "188.114.97.249:500",
    "endpoint_port": "500",
    "ip": "104.28.x.x",
    "colo": "ARN",
    "loc": "RU",
    "status": "on",
    "on": true
  },
  "cron": {
    "installed": true,
    "uses_flock": true
  }
}
```

Поле `healthy=true` означает, что WARP установлен, `wireproxy` активен, SOCKS5 слушает, Cloudflare trace даёт `warp=on`, cron установлен и использует `flock`.

---

## Режимы scan / ремонта endpoint

Быстрый scan:

```bash
warpwp --quick-scan
```

Обычный scan:

```bash
warpwp --check
```

Глубокий scan:

```bash
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
/var/log/warp-check.log
/var/lock/warpwp-check.lock
```

Бэкапы создаются здесь:

```text
/root/warp-wireproxy-native-backup/
```

---

## Cron-автопроверка и flock lock

После `warpwp --install` или `warpwp --install-cron` создаётся cron-файл:

```text
/etc/cron.d/warp-wireproxy-check
```

Пример содержимого:

```cron
*/10 * * * * root flock -n /var/lock/warpwp-check.lock /usr/local/bin/warp-wireproxy-native.sh --check --scan-count 25 >> /var/log/warp-check.log 2>&1
```

Что делает cron:

1. Проверяет локальный SOCKS5 `127.0.0.1:40000`.
2. Делает запрос к Cloudflare trace.
3. Если есть `warp=on` — ничего не меняет.
4. Если WARP не отвечает — проверяет текущий endpoint.
5. Проверяет хорошие endpoint'ы из кэша.
6. Проверяет fallback endpoint'ы.
7. При необходимости запускает random scan.
8. Выбирает рабочий endpoint.
9. Подменяет `Endpoint` в `warp.conf` и `proxy.conf`.
10. Перезапускает `wireproxy`.

Логи:

```bash
tail -n 80 /var/log/warp-check.log
```

---

## Кэш endpoint'ов

```bash
cat /etc/wireguard/warp-endpoints.good
cat /etc/wireguard/warp-endpoints.bad 2>/dev/null
```

Формат `good`:

```text
endpoint    time_total    colo    loc    timestamp
```

Формат `bad`:

```text
endpoint    fail_count    timestamp
```

Если endpoint получил 3+ ошибки, он пропускается 24 часа.

---

## Doctor / диагностика

```bash
warpwp --doctor
```

Проверяет root, зависимости, `wireproxy.service`, SOCKS5-порт, Cloudflare trace, cron, `flock`, логи и основные конфиги.

Пример здорового состояния:

```text
[OK] wireproxy active
[OK] SOCKS5 порт 40000 слушает
[OK] Cloudflare trace: warp=on
[OK] cron установлен: /etc/cron.d/warp-wireproxy-check
[OK] cron использует flock lock
Итог: OK=19 WARN=0 FAIL=0
```

---

## Проверка работы WARP

```bash
curl -m 10 -s -x socks5h://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace | grep -E 'ip=|colo=|loc=|warp='
```

Хороший результат:

```text
warp=on
```

---

## 3x-ui / Xray

Вывести блоки:

```bash
warpwp --xray
```

Outbounds:

```json
{
  "tag": "WARP-socks5",
  "protocol": "socks",
  "settings": {
    "servers": [
      {
        "address": "127.0.0.1",
        "port": 40000
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
```

Routing вести на:

```json
"outboundTag": "WARP"
```

---

## zapret4rocket

Вывести строки:

```bash
warpwp --zapret
```

Рекомендуемая строка:

```bash
NFQWS_PORTS_UDP=443,2408,1843,1010,500,1701,4500,4443,8443,8095
```

Локальный порт `40000` — это SOCKS5 wireproxy. Его в zapret добавлять не нужно.

---

## Ручной запуск native-скрипта

Установка напрямую:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warp-wireproxy-native.sh?nocache=$(date +%s)")
```

Проверить и починить endpoint:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warp-wireproxy-native.sh?nocache=$(date +%s)") --check --scan-count 25
```

Глубокий scan:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warp-wireproxy-native.sh?nocache=$(date +%s)") --check --scan-count 150
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

Проверить версии:

```bash
warpwp --version
/usr/local/bin/warp-wireproxy-native.sh --version
```

---

## Удаление и переустановка

Безопасное удаление:

```bash
warpwp --remove
```

Полная очистка:

```bash
warpwp --purge
```

После очистки:

```bash
warpwp --install
```

---

## CI / проверка скриптов

Workflow:

```text
.github/workflows/shellcheck.yml
```

Проверяет все `*.sh`:

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
