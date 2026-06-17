# TODO

План ближайших улучшений для `WARP WireProxy Manager`.

## Выполнено

- [x] `warpwp --xray`
  - Выводит только блоки для 3x-ui / Xray.

- [x] `warpwp --zapret`
  - Выводит только информацию для zapret4rocket.

- [x] `warpwp --wg-paste`
  - Позволяет вставить содержимое WireGuard `.conf` прямо в терминал.
  - Не требует загружать файл на сервер.
  - После вставки ждёт короткую паузу и выводит JSON для окна 3x-ui/Xray.

- [x] `warpwp --wg-json FILE`
  - Конвертирует обычный WireGuard `.conf` из файла в JSON для окна 3x-ui/Xray.
  - Алиас: `warpwp --wg-convert FILE`.
  - Поддерживает `PrivateKey`, несколько `Address`, `MTU`, `PublicKey`, `PresharedKey`, `Endpoint`, `AllowedIPs`, `PersistentKeepalive`.

- [x] `warpwp --quick-scan`
  - Быстрый ремонт endpoint.
  - Использует `scan-count=15`.

- [x] `warpwp --deep-scan`
  - Глубокий ремонт endpoint.
  - Использует `scan-count=150`.

- [x] `warpwp --status-json`
  - JSON-статус для внешних панелей/автоматизации.
  - Алиас: `warpwp --json`.
  - Включает версии, health, scheduler, service, socks5, WARP trace, cron/flock, timer, логи и cache paths.

- [x] systemd timer как альтернатива cron.
  - `warpwp --install-timer [минуты]`.
  - `warpwp --timer-status`.
  - `warpwp --remove-timer`.
  - Timer запускает endpoint check с выбранным интервалом.

- [x] Взаимоисключающие scheduler modes.
  - `warpwp --install-cron` включает cron и отключает timer.
  - `warpwp --install-timer` включает timer и отключает cron.
  - `warpwp --scheduler-status` показывает `cron`, `systemd_timer`, `both` или `none`.

- [x] Запрос интервала timer в минутах.
  - По умолчанию 10 минут.
  - Можно передать без интерактива: `warpwp --install-timer 15`.

- [x] `flock` lock для cron/check/timer.
- [x] good endpoint cache: `/etc/wireguard/warp-endpoints.good`.
- [x] bad endpoint cache: `/etc/wireguard/warp-endpoints.bad`.
- [x] blacklist плохих endpoint'ов на 24 часа после 3 ошибок.
- [x] `warpwp --doctor`.
- [x] `warpwp --install-cron`.
- [x] атомарный self-update через временный файл + `mv`.
- [x] GitHub Actions workflow: `bash -n` + `shellcheck` для всех `*.sh`.
- [x] Локальный скрипт проверки `scripts/check.sh`.
  - Запускает `bash -n` для всех `*.sh`.
  - Запускает `shellcheck`, если он установлен.
  - GitHub Actions теперь использует этот же скрипт.
- [x] Лёгкий режим `warp-wireproxy-native.sh --check`.
  - Не запускает `apt update` / `apt install` при cron/timer-проверках.
- [x] Исправлены legacy-ссылки `Kuzz007/test` на текущий репозиторий.
- [x] `warp-wireproxy-auto.sh` переведён в deprecated-wrapper.

## Возможные следующие задачи

- [ ] автообновление README-команд при изменении версии.
- [ ] release tags / changelog для версий.
- [ ] проверка CI после каждого push и исправление shellcheck warning.
- [ ] OpenRC unit для Alpine без systemd, если понадобится.
