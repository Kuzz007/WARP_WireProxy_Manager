# TODO

План ближайших улучшений для `WARP WireProxy Manager`.

## Ближайшее

- [ ] `warpwp --xray`
  - Выводить только блоки для 3x-ui / Xray.
  - Включить:
    - `WARP-socks5` outbound;
    - `WARP` outbound через `proxySettings`;
    - пример routing для OpenAI/ChatGPT;
    - короткое предупреждение, что routing должен идти на `outboundTag: "WARP"`, а не на `WARP-socks5`.

- [ ] `warpwp --zapret`
  - Выводить только информацию для zapret4rocket.
  - Включить:
    - текущий WARP endpoint;
    - UDP-порт текущего endpoint;
    - рекомендуемую строку `NFQWS_PORTS_UDP`;
    - команды открытия конфига и перезапуска zapret.

## Надёжность

- [x] `flock` lock для cron/check.
- [x] good endpoint cache: `/etc/wireguard/warp-endpoints.good`.
- [x] bad endpoint cache: `/etc/wireguard/warp-endpoints.bad`.
- [x] blacklist плохих endpoint'ов на 24 часа после 3 ошибок.
- [x] `warpwp --doctor`.
- [x] `warpwp --install-cron`.
- [x] атомарный self-update через временный файл + `mv`.
- [x] GitHub Actions workflow: `bash -n` + `shellcheck` для всех `*.sh`.

## Возможные следующие задачи

- [ ] `warpwp --quick-scan` — быстрый scan 10–25 endpoint'ов.
- [ ] `warpwp --deep-scan` — глубокий scan 100–200 endpoint'ов.
- [ ] `warpwp --status-json` — JSON-статус для внешних панелей/автоматизации.
- [ ] systemd timer как альтернатива cron.
- [ ] автообновление README-команд при изменении версии.
