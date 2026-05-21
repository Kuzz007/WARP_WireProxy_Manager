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
  - Включает версии, health, service, socks5, WARP trace, cron/flock, логи и cache paths.

- [x] `flock` lock для cron/check.
- [x] good endpoint cache: `/etc/wireguard/warp-endpoints.good`.
- [x] bad endpoint cache: `/etc/wireguard/warp-endpoints.bad`.
- [x] blacklist плохих endpoint'ов на 24 часа после 3 ошибок.
- [x] `warpwp --doctor`.
- [x] `warpwp --install-cron`.
- [x] атомарный self-update через временный файл + `mv`.
- [x] GitHub Actions workflow: `bash -n` + `shellcheck` для всех `*.sh`.

## Возможные следующие задачи

- [ ] systemd timer как альтернатива cron.
- [ ] автообновление README-команд при изменении версии.
