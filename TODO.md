# TODO

План ближайших улучшений для `WARP WireProxy Manager`.

## Выполнено

- [x] `warpwp --xray`
  - Выводит только блоки для 3x-ui / Xray.

- [x] `warpwp --zapret`
  - Выводит только информацию для zapret4rocket.

- [x] `warpwp --quick-scan`
  - Быстрый ремонт endpoint.
  - Использует `scan-count=15`.

- [x] `warpwp --deep-scan`
  - Глубокий ремонт endpoint.
  - Использует `scan-count=150`.

- [x] `warpwp --status-json`
  - JSON-статус для внешних панелей/автоматизации.
  - Алиас: `warpwp --json`.
  - Включает версии, health, service, socks5, WARP trace, cron/flock, timer, логи и cache paths.

- [x] systemd timer как альтернатива cron.
  - `warpwp --install-timer`
  - `warpwp --timer-status`
  - `warpwp --remove-timer`
  - Timer запускает endpoint check каждые 10 минут.

- [x] `flock` lock для cron/check/timer.
- [x] good endpoint cache: `/etc/wireguard/warp-endpoints.good`.
- [x] bad endpoint cache: `/etc/wireguard/warp-endpoints.bad`.
- [x] blacklist плохих endpoint'ов на 24 часа после 3 ошибок.
- [x] `warpwp --doctor`.
- [x] `warpwp --install-cron`.
- [x] атомарный self-update через временный файл + `mv`.
- [x] GitHub Actions workflow: `bash -n` + `shellcheck` для всех `*.sh`.

## Возможные следующие задачи

- [ ] автообновление README-команд при изменении версии.
- [ ] release tags / changelog для версий.
- [ ] проверка CI после каждого push и исправление shellcheck warning.
