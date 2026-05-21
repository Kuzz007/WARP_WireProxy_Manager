#!/usr/bin/env bash
# scripts/check.sh
# Локальная проверка bash-скриптов проекта.

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Bash syntax check =="
while IFS= read -r -d '' file; do
  echo "bash -n $file"
  bash -n "$file"
done < <(find . -type f -name '*.sh' -not -path './.git/*' -print0)

echo
if command -v shellcheck >/dev/null 2>&1; then
  echo "== ShellCheck =="
  find . -type f -name '*.sh' -not -path './.git/*' -print0 | \
    xargs -0 shellcheck --severity=warning --external-sources
else
  echo "== ShellCheck =="
  echo "shellcheck не установлен, пропускаю."
  echo "Установить на Ubuntu/Debian: apt install -y shellcheck"
fi

echo
printf '[OK] checks completed\n'
