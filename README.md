# WARP WireProxy Manager

`WARP WireProxy Manager` — это неинтерактивный установщик и менеджер для схемы:

```text
3x-ui / Xray → socks5://127.0.0.1:40000 → wireproxy → Cloudflare WARP → internet
```

Проект рассчитан на VPS с Linux/systemd. Основная цель — быстро поднять Cloudflare WARP как локальный SOCKS5 outbound для 3x-ui/Xray, автоматически подобрать рабочий WARP endpoint и поддерживать его живым через cron-проверку.

Репозиторий:

```text
https://github.com/Kuzz007/WARP_WireProxy_Manager
```

Текущая основная версия:

```text
warpwp v1.1.3
warp-wireproxy-native.sh v1.1.0
```

---

## Быстрый старт

### 1. Установить менеджер

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warpwp.sh?nocache=$(date +%s)") --install-manager
```

Если raw-кэш GitHub отдаёт старую версию, можно поставить через GitHub API:

```bash
curl -fsSL \
  -H "Accept: application/vnd.github.raw" \
  "https://api.github.com/repos/Kuzz007/WARP_WireProxy_Manager/contents/warpwp.sh?ref=main" \
  -o /usr/local/bin/warpwp

chmod +x /usr/local/bin/warpwp
```

### 2. Открыть меню

```bash
warpwp
```

### 3. Выбрать пункт

```text
1) Установить / обновить WARP + wireproxy + cron
```

### 4. Проверить состояние

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

- Кэширует хорошие endpoint'ы:

```text
/etc/wireguard/warp-endpoints.good
```

- Кэширует плохие endpoint'ы:

```text
/etc/wireguard/warp-endpoints.bad
```

- Использует blacklist: endpoint с 3+ ошибками не проверяется 24 часа.
- Использует `flock`, чтобы cron/check не запускались параллельно.
- Создаёт короткую команду:

```bash
warpwp
```

- Ставит cron-автопроверку endpoint'а.
- Если WARP умер — автоматически пересканирует endpoint'ы, подменит рабочий и перезапустит `wireproxy`.
- Показывает готовые блоки для 3x-ui/Xray.
- Показывает готовые строки для zapret4rocket.

---

## Меню

```text
============================================================
 WARP + wireproxy manager v1.1.3
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
| `warpwp --doctor` | Расширенная диагностика |
| `warpwp --check` | Проверить WARP и при необходимости заменить endpoint |
| `warpwp --xray` | Показать только блоки для 3x-ui/Xray |
| `warpwp --zapret` | Показать только строки для zapret4rocket |
| `warpwp --logs` | Показать логи cron и `wireproxy` |
| `warpwp --memo` | Показать полную памятку для 3x-ui/zapret |
| `warpwp --update` | Обновить локальные скрипты |
| `warpwp --self-update` | То же самое, что `--update` |
| `warpwp --version` | Показать версию менеджера |
| `warpwp --remove` | Безопасно удалить компоненты менеджера |
| `warpwp --purge` | Жёстко удалить WARP/wireproxy/wgcf/warp-cli/fscarmen-следы |

---

## Что ставится на сервер

Основные файлы:

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

Зачем нужен `flock`:

```text
если предыдущий endpoint scan ещё идёт, новый cron-запуск не начнётся
нет параллельной перезаписи proxy.conf
нет двойного restart wireproxy
```

Лог:

```bash
tail -n 80 /var/log/warp-check.log
```

Что делает cron:

1. Проверяет локальный SOCKS5 `127.0.0.1:40000`.
2. Делает запрос к Cloudflare trace.
3. Если есть `warp=on` — ничего не меняет.
4. Если WARP не отвечает — проверяет текущий endpoint.
5. Проверяет хорошие endpoint'ы из кэша.
6. Проверяет fallback endpoint'ы.
7. При необходимости запускает random scan.
8. Выбирает рабочий и быстрый endpoint.
9. Подменяет `Endpoint` в `warp.conf` и `proxy.conf`.
10. Перезапускает `wireproxy`.

---

## Кэш endpoint'ов

Хорошие endpoint'ы:

```bash
cat /etc/wireguard/warp-endpoints.good
```

Плохие endpoint'ы:

```bash
cat /etc/wireguard/warp-endpoints.bad 2>/dev/null
```

Формат `good`:

```text
endpoint    time_total    colo    loc    timestamp
```

Пример:

```text
188.114.97.249:500    0    quick    quick    1779364491
```

`time_total=0 quick quick` означает, что endpoint был подтверждён быстрой проверкой `--check`, а не полным сканом.

Формат `bad`:

```text
endpoint    fail_count    timestamp
```

Если endpoint получил 3+ ошибки, он пропускается 24 часа.

---

## Doctor / диагностика

Запуск:

```bash
warpwp --doctor
```

Проверяет:

```text
root права
curl/systemctl/ss/grep/awk/sed
flock
/usr/local/bin/warpwp
/usr/local/bin/warp-wireproxy-native.sh
warp.conf
proxy.conf
wireproxy.service
wireproxy active
SOCKS5 127.0.0.1:40000
Cloudflare trace warp=on
cron
cron использует flock lock
лог
```

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
ip=...
colo=...
loc=...
warp=on
```

---

## 3x-ui / Xray

Быстро вывести только блоки для Xray:

```bash
warpwp --xray
```

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

Быстро вывести только строки для zapret4rocket:

```bash
warpwp --zapret
```

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
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warp-wireproxy-native.sh?nocache=$(date +%s)")
```

Проверить и починить endpoint:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warp-wireproxy-native.sh?nocache=$(date +%s)") --check --scan-count 25
```

Более глубокое сканирование:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warp-wireproxy-native.sh?nocache=$(date +%s)") --scan-count 100
```

С ручными endpoint'ами:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warp-wireproxy-native.sh?nocache=$(date +%s)") --endpoints "162.159.192.244:1843 162.159.195.100:1010"
```

---

## Обновление

Обновить локальные скрипты:

```bash
warpwp --update
```

или:

```bash
warpwp --self-update
```

Обновить сам менеджер из GitHub напрямую:

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/Kuzz007/WARP_WireProxy_Manager/main/warpwp.sh?nocache=$(date +%s)") --install-manager
```

Обновить через GitHub API, если raw-кэш отдаёт старую версию:

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

Безопасное удаление компонентов менеджера:

```bash
warpwp --remove
```

Удаляет только основные компоненты менеджера:

```text
/usr/local/bin/warp-wireproxy-native.sh
/etc/cron.d/warp-wireproxy-check
/etc/systemd/system/wireproxy.service
/etc/wireguard/warp.conf
/etc/wireguard/proxy.conf
/etc/wireguard/warp-account.json
/etc/wireguard/warp-private.key
```

Полная жёсткая очистка:

```bash
warpwp --purge
```

Дополнительно удаляет возможные следы старых установок:

```text
wireproxy binary
warp-cli
warp-svc
wgcf
старые fscarmen файлы
/etc/wireguard
старые backup-папки
```

После очистки можно установить заново:

```bash
warpwp --install
```

---

## CI / проверка скриптов

В репозитории есть GitHub Actions workflow:

```text
.github/workflows/shellcheck.yml
```

Он проверяет все `*.sh`:

```text
bash -n
shellcheck --severity=warning
```

Это должно ловить синтаксические ошибки до запуска скриптов на сервере.

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
TODO.md                    список дальнейших улучшений
.github/workflows/         CI-проверки bash-скриптов
```
