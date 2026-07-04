# WARP WireProxy Manager

`WARP WireProxy Manager` — неинтерактивный установщик и менеджер для схемы:

```text
3x-ui / Xray → socks5://127.0.0.1:40000 → wireproxy → Cloudflare WARP → internet
```

Проект рассчитан на VPS с Linux + systemd. Цель — быстро поднять Cloudflare WARP как **локальный SOCKS5 outbound** для 3x-ui/Xray, автоматически подобрать рабочий WARP endpoint и поддерживать его живым через один scheduler: cron или systemd timer.

> Alpine/OpenRC как отдельный init-режим не поддерживается: для автозапуска нужен `systemctl`.

## Важно про маршрутизацию

Этот проект **не должен** превращать весь VPS в WARP-VPN клиент. WARP используется только через `wireproxy` и локальный SOCKS5 `127.0.0.1:40000`.

Не запускай WARP-конфиг через `wg-quick`:

```bash
wg-quick up warp
systemctl enable --now wg-quick@warp
```

Если системный `wg-quick@warp` поднимет full-tunnel WARP, входящие подключения могут сломаться: SSH/443 приходят на обычный интерфейс VPS, а ответы уходят через WARP. Это выглядит как «сервер в интернете не отвечает», хотя пакеты до него доходят.

Начиная с `warpwp v1.2.1` и `warp-wireproxy-native.sh v1.1.4` добавлена защита:

- `warpwp --fix-routing` отключает опасный системный WARP full-tunnel и не трогает `wireproxy` SOCKS5;
- `warpwp --doctor` показывает routing guard: `ip rule`, `table 51820`, `interface warp`, `wg-quick@warp`;
- `warpwp --install`, `--check`, `--quick-scan`, `--deep-scan` перед работой очищают конфликтующий system-WARP routing;
- `/etc/wireguard/warp.conf` создаётся как guard-файл: случайный `wg-quick up warp` завершится ошибкой до добавления full-tunnel маршрутов;
- рабочий конфиг для `wireproxy` остаётся `/etc/wireguard/proxy.conf`.

Аварийное восстановление после сломанного WARP routing:

```bash
warpwp --fix-routing
ip route get 1.1.1.1
ip route get <твой-admin-ip>
```

Нормально, когда ответы идут через основной интерфейс VPS, например `ens3`, а не через `warp` / `table 51820`.

---

Репозиторий:

```text
https://github.com/Kuzz007/WARP_WireProxy_Manager
```

Текущая версия:

```text
warpwp v1.2.1
warp-wireproxy-native.sh v1.1.4
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

Починить опасную системную WARP-маршрутизацию:

```bash
warpwp --fix-routing
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
| `warpwp --doctor` | Расширенная диагностика + routing guard |
| `warpwp --fix-routing` | Убрать системный WARP full-tunnel, не трогая `wireproxy` SOCKS5 |
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
 WARP + wireproxy manager v1.2.1
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
23) Fix routing / убрать системный WARP full-tunnel
 0) Выход
============================================================
```

---

## Автопроверка без лишнего apt update

Cron и systemd timer вызывают native-скрипт в режиме `--check`:

```bash
warp-wireproxy-native.sh --check --scan-count 25
```

Режим `--check` делает лёгкую проверку уже установленных команд и не запускает `apt update` / `apt install`. Это важно для cron/timer, чтобы каждые 10 минут не дёргать пакетный менеджер.

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
