# TODO

План ближайших улучшений для `WARP WireProxy Manager`.

## Выполнено

- [x] `warpwp --xray`
  - Выводит только блоки для 3x-ui / Xray.
  - Включает:
    - `WARP-socks5` outbound;
    - `WARP` outbound через `proxySettings`;
    - пример routing для OpenAI/ChatGPT;
    - предупреждение, что routing должен идти на `outboundTag: "WARP"`, а не на `WARP-socks5`.

- [x] `warpwp --zapret`
  - Выводит только информацию для zapret4rocket.
  - Включает:
    - текущий WARP endpoint;
    - UDP-порт текущего endpoint;
    - рекомендуемую строку `NFQWS_PORTS_UDP`;
    - команды открытия конфига и перезапуска zapret.

- [x] `warpwp --quick-scan`
  - Быстрый ремонт endpoint.
  - Использует `scan-count=15`.

- [x] `warpwp --deep-scan`
  - Глубокий ремонт endpoint.
  - Использует `scan-count=150`.

- [x] `flock` lock для cron/check.
- [x] good endpoint cache: `/etc/wireguard/warp-endpoints.good`.
- [x] bad endpoint cache: `/etc/wireguard/warp-endpoints.bad`.
- [x] blacklist плохих endpoint'ов на 24 часа после 3 ошибок.
- [x] `warpwp --doctor`.
- [x] `warpwp --install-cron`.
- [x] атомарный self-update через временный файл + `mv`.
- [x] GitHub Actions workflow: `bash -n` + `shellcheck` для всех `*.sh`.

## Возможные следующие задачи

- [ ] `warpwp --status-json` — JSON-статус для внешних панелей/автоматизации.
- [ ] systemd timer как альтернатива cron.
- [ ] автообновление README-команд при изменении версии.
