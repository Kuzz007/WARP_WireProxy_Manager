# WARP WireProxy Manager

Автоматический установщик и менеджер для схемы:

```text
3x-ui / Xray → socks5://127.0.0.1:40000 → wireproxy → Cloudflare WARP → internet
```

Проект рассчитан на VPS с Linux/systemd. Основная цель — быстро поднять WARP как локальный SOCKS5 outbound для 3x-ui/Xray, автоматически подобрать рабочий endpoint Cloudflare WARP и поддерживать его живым через cron-проверку.

---

## Что умеет

- Устанавливает WARP + `wireproxy` без интерактивного меню `fscarmen`.
- Сам регистрирует WARP-устройство через Cloudflare API.
- Создаёт:
  - `/etc/wireguard/warp.conf`
  - `/etc/wireguard/proxy.conf`
  - `/etc/systemd/system/wireproxy.service`
- Поднимает локальный SOCKS5:

```text
127.0.0.1:40000
```

- Сканирует WARP endpoint'ы Cloudflare.
- Выбирает самый быстрый endpoint, где Cloudflare trace показывает:

```text
warp=on
```

- Создаёт короткую команду:

```bash
warpwp
```

- Ставит cron-автопроверку endpoint'а.
- Если WARP умер — автоматически пересканирует endpoint'ы, подменит рабочий и перезапустит `wireproxy`.
- Показывает готовые блоки для 3x-ui/Xray и zapret4rocket.

---

## Быстрая установка

Установить менеджер:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/test/main/warpwp.sh?nocache=$(date +%s)") --install-manager
```

Открыть меню:

```bash
warpwp
```

Дальше выбери пункт:

```text
1) Установить / обновить WARP + wireproxy + cron
```

---

## Меню

```text
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
 8) Показать памятку для 3x-ui / zapret
 0) Выход
============================================================
```

---

## Команды без меню

Установить или обновить всё:

```bash
warpwp --install
```

Проверить состояние:

```bash
warpwp --status
```

Проверить WARP и при необходимости заменить endpoint:

```bash
warpwp --check
```

Показать памятку для 3x-ui/zapret:

```bash
warpwp --memo
```

Показать логи:

```bash
warpwp --logs
```

Удалить WARP/wireproxy/cron:

```bash
warpwp --remove
```

Обновить локальные скрипты:

```bash
warpwp --update
```

---

## Что ставится на сервер

Основные файлы:

```text
/usr/local/bin/warpwp
/usr/local/bin/warp-wireproxy-native.sh
/etc/wireguard/warp.conf
/etc/wireguard/proxy.conf
/etc/systemd/system/wireproxy.service
/etc/cron.d/warp-wireproxy-check
/var/log/warp-check.log
```

Бэкапы создаются здесь:

```text
/root/warp-wireproxy-native-backup/
```

---

## Cron-автопроверка

После `warpwp --install` создаётся cron-файл:

```text
/etc/cron.d/warp-wireproxy-check
```

Пример содержимого:

```cron
*/10 * * * * root /usr/local/bin/warp-wireproxy-native.sh --check --scan-count 25 >> /var/log/warp-check.log 2>&1
```

Лог:

```bash
tail -n 80 /var/log/warp-check.log
```

Что делает cron:

1. Проверяет локальный SOCKS5 `127.0.0.1:40000`.
2. Делает запрос к Cloudflare trace.
3. Если есть `warp=on` — ничего не меняет.
4. Если WARP не отвечает — сканирует endpoint'ы.
5. Выбирает рабочий и быстрый endpoint.
6. Подменяет `Endpoint` в `warp.conf` и `proxy.conf`.
7. Перезапускает `wireproxy`.

---

## Проверка работы WARP

```bash
curl -m 10 -s -x socks5h://127.0.0.1:40000 https://www.cloudflare.com/cdn-cgi/trace | grep -E 'ip=|colo=|loc=|warp='
```

Хороший результат:

```text
ip=...
colo=...
loc=...
warp=on
```

---

## 3x-ui / Xray outbounds

Добавь эти outbounds в конфиг Xray/3x-ui:

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

Важно: в routing правилах используй:

```json
"outboundTag": "WARP"
```

Не направляй правила напрямую на `WARP-socks5`. `WARP-socks5` — это технический промежуточный outbound.

---

## Пример routing для OpenAI / ChatGPT

```json
{
  "type": "field",
  "domain": [
    "domain:openai.com",
    "domain:chatgpt.com",
    "domain:oaistatic.com",
    "domain:oaiusercontent.com"
  ],
  "outboundTag": "WARP"
}
```

---

## zapret4rocket

Для WARP важен внешний UDP-порт endpoint'а, а не локальный порт `40000`.

Локальный порт:

```text
127.0.0.1:40000
```

это SOCKS5 `wireproxy`. Его в zapret добавлять не нужно.

Рекомендуемая строка:

```bash
NFQWS_PORTS_UDP=443,2408,1843,1010,500,1701,4500,4443,8443,8095
```

Открыть конфиг zapret4rocket:

```bash
nano /opt/zapret/config
```

Перезапустить:

```bash
/opt/zapret/init.d/sysv/zapret restart
```

или:

```bash
systemctl restart zapret
```

---

## Ручной запуск native-скрипта

Если менеджер не нужен, можно запустить основной установщик напрямую:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/test/main/warp-wireproxy-native.sh?nocache=$(date +%s)")
```

Проверить и починить endpoint:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/test/main/warp-wireproxy-native.sh?nocache=$(date +%s)") --check --scan-count 25
```

Более глубокое сканирование:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/test/main/warp-wireproxy-native.sh?nocache=$(date +%s)") --scan-count 100
```

С ручными endpoint'ами:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/test/main/warp-wireproxy-native.sh?nocache=$(date +%s)") --endpoints "162.159.192.244:1843 162.159.195.100:1010"
```

---

## Очистка и переустановка

Через менеджер:

```bash
warpwp --remove
warpwp --install
```

Если нужно вручную посмотреть, что связано с WARP:

```bash
systemctl list-unit-files | grep -Ei 'warp|wireproxy|wgcf|wg-quick' || true
ps aux | grep -Ei 'warp|wireproxy|wgcf|cloudflare|warp-cli|warp-svc' | grep -v grep || true
ls -la /etc/wireguard/ 2>/dev/null || true
```

---

## Troubleshooting

### `apt update` падает из-за стороннего репозитория

Например:

```text
E: The repository 'https://packagecloud.io/ookla/speedtest-cli/ubuntu noble Release' does not have a Release file.
```

Найти источник:

```bash
grep -Rni "packagecloud.io/ookla" /etc/apt/
```

Закомментировать:

```bash
grep -Rli "packagecloud.io/ookla" /etc/apt/ | xargs -r sed -i '/packagecloud\.io\/ookla/s/^/# /'
apt update
```

Если активна строка `deb-src`, её тоже нужно закомментировать:

```bash
sed -i 's/^deb-src /# deb-src /' /etc/apt/sources.list.d/ookla_speedtest-cli.list
apt update
```

---

### Проверить `wireproxy`

```bash
systemctl status wireproxy --no-pager -l | head -80
journalctl -u wireproxy -n 80 --no-pager
```

---

### Проверить порт SOCKS5

```bash
ss -lntup | grep ':40000'
```

---

### Проверить текущий endpoint

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
```
