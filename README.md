# WARP WireProxy Manager

`WARP WireProxy Manager` — неинтерактивный установщик и менеджер для схемы:

```text
3x-ui / Xray → socks5://127.0.0.1:40000 → wireproxy → Cloudflare WARP → internet
```

Проект рассчитан на VPS с Linux + systemd. Цель — быстро поднять Cloudflare WARP как локальный SOCKS5 outbound для 3x-ui/Xray, автоматически подобрать рабочий WARP endpoint и поддерживать его живым через один scheduler: cron или systemd timer.

> Alpine/OpenRC как отдельный init-режим не поддерживается: для автозапуска нужен `systemctl`.

Репозиторий:

```text
https://github.com/Kuzz007/WARP_WireProxy_Manager
```

Текущая версия:

```text
warpwp v1.2.0
warp-wireproxy-native.sh v1.1.2
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

Проверить состояние:

```bash
warpwp --doctor
warpwp --status-json
```

---

## Основные команды

| Команда | Что делает |
|---|---|
| `warpwp` | Открыть меню |
| `warpwp --install` | Установить/обновить WARP + wireproxy + cron |
| `warpwp --install-cron` | Включить cron и отключить timer |
| `warpwp --install-timer [минуты]` | Включить timer и отключить cron |
| `warpwp --timer-status` | Показать статус systemd timer |
| `warpwp --scheduler-status` | Показать активный scheduler |
| `warpwp --status` | Показать состояние |
| `warpwp --status-json` | Показать JSON-статус |
| `warpwp --doctor` | Расширенная диагностика |
| `warpwp --check` | Обычный ремонт endpoint, `scan-count=25` |
| `warpwp --quick-scan` | Быстрый ремонт endpoint, `scan-count=15` |
| `warpwp --deep-scan` | Глубокий ремонт endpoint, `scan-count=150` |
| `warpwp --xray` | Показать блоки для 3x-ui/Xray |
| `warpwp --zapret` | Показать строки для zapret4rocket |
| `warpwp --wg-paste` | Вставить WireGuard `.conf` в терминал и получить JSON |
| `warpwp --wg-json FILE` | Конвертировать WireGuard `.conf` в JSON для 3x-ui/Xray |
| `warpwp --wg-convert FILE` | Алиас для `--wg-json` |
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
 WARP + wireproxy manager v1.2.0
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
```

---

## Автопроверка без лишнего apt update

Cron и systemd timer вызывают native-скрипт в режиме `--check`:

```bash
warp-wireproxy-native.sh --check --scan-count 25
```

Начиная с `warp-wireproxy-native.sh v1.1.2`, режим `--check` делает только лёгкую проверку уже установленных команд и не запускает `apt update` / `apt install`. Это важно для cron/timer, чтобы каждые 10 минут не дёргать пакетный менеджер.

---

## WireGuard `.conf` → JSON для 3x-ui/Xray

Из файла:

```bash
warpwp --wg-json /root/wg0.conf
```

Вставкой прямо в терминал:

```bash
warpwp --wg-paste
```

Обычный WireGuard config:

```ini
[Interface]
PrivateKey = CLIENT_PRIVATE_KEY
Address = 10.0.0.2/32
Address = fd00::2/128
DNS = 1.1.1.1
MTU = 1280

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = 1.2.3.4:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

Будет преобразован в формат:

```json
{
  "protocol": "wireguard",
  "settings": {
    "mtu": 1280,
    "secretKey": "CLIENT_PRIVATE_KEY",
    "address": [
      "10.0.0.2/32",
      "fd00::2/128"
    ],
    "workers": 2,
    "peers": [
      {
        "publicKey": "SERVER_PUBLIC_KEY",
        "allowedIPs": [
          "0.0.0.0/0",
          "::/0"
        ],
        "endpoint": "1.2.3.4:51820",
        "keepAlive": 25
      }
    ],
    "noKernelTun": false
  }
}
```

Конвертер поддерживает несколько строк `Address`, поэтому IPv4 и IPv6 не теряются.

После создания outbound задай tag, например:

```text
WG
```

И используй routing на:

```json
{
  "type": "field",
  "domain": [
    "domain:openai.com",
    "domain:chatgpt.com"
  ],
  "outboundTag": "WG"
}
```

---

## Scheduler modes

Cron и systemd timer взаимоисключающие.

Включить cron-режим:

```bash
warpwp --install-cron
```

Включить timer-режим:

```bash
warpwp --install-timer
```

Передать интервал сразу без вопроса:

```bash
warpwp --install-timer 15
```

Проверить активный scheduler:

```bash
warpwp --scheduler-status
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

---

## 3x-ui / Xray

```bash
warpwp --xray
```

Routing вести на:

```json
"outboundTag": "WARP"
```

Не направляй routing напрямую на `WARP-socks5`; этот outbound используется как промежуточный.

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
install-warp-check.sh      отдельный минимальный установщик cron-проверки
warp-wireproxy-auto.sh     deprecated-wrapper для обратной совместимости
TODO.md                    список дальнейших улучшений
.github/workflows/         CI-проверки bash-скриптов
```
