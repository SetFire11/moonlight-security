#!/bin/bash
# Ставит только меню Moonlight Security. Защиту включают из пунктов меню.
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Запуск только от root"; exit 1; }

SRC="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DEST="/opt/moonlight-security"

if [[ "$SRC" != "$DEST" ]]; then
  mkdir -p "$DEST"
  cp -a "$SRC/." "$DEST/"
fi

chmod +x "$DEST/install.sh" "$DEST/moonlight.sh" \
  "$DEST/trafficguard/apply.sh" "$DEST/trafficguard/manager.sh" \
  "$DEST/trafficguard/traffic-guard" \
  "$DEST/vendor/server-shield/"*.sh \
  "$DEST/vendor/server-shield/modules/"*.sh \
  "$DEST/vendor/remnanode-antiscan/install.sh" \
  "$DEST/vendor/remnanode-antiscan/scripts/"*.sh

ln -sfn "$DEST/moonlight.sh" /usr/local/bin/moonlight

echo
echo "Moonlight Security установлен."
echo "Дальше на сервере: moonlight"
echo
echo "1  Traffic Guard"
echo "2  AntiScan"
echo "3  Server Shield"
echo "4  Статус"
echo "5  Нода"
echo "6  Обновление"
