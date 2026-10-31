#!/bin/bash
# Moonlight Security — отдельные пункты, без общей простыни правил.
set -u
CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo "Запуск только от root"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pause() { read -r -p $'\n[Enter] назад...' < /dev/tty || true; }

traffic_guard() {
  bash "$ROOT/trafficguard/apply.sh"
  echo
  echo "Открываю меню списков."
  bash "$ROOT/trafficguard/manager.sh"
}

antiscan() {
  echo -e "${YELLOW}RemnaNode AntiScan меняет UFW, SSH, Fail2Ban или CrowdSec только после выбора в его меню.${NC}"
  echo "Неподтверждённые правила откатятся сами. Проверь новое SSH-подключение, затем confirm."
  echo
  bash "$ROOT/vendor/remnanode-antiscan/install.sh"
}

server_shield() {
  if command -v shield >/dev/null 2>&1 && [[ -d /opt/server-shield/modules ]]; then
    shield
    return
  fi
  echo -e "${YELLOW}Server Shield ставит UFW, Fail2Ban и может отключить вход по паролю.${NC}"
  echo "Запускай, только если SSH-ключ уже лежит на сервере."
  echo
  export MOONLIGHT_SHIELD_SRC="$ROOT/vendor/server-shield"
  bash "$ROOT/vendor/server-shield/install.sh"
}

while true; do
  clear
  echo -e "${CYAN}Moonlight Security${NC}"
  echo "Три защиты отдельно. Одним пунктом они не включаются вместе."
  echo
  echo "  1  Traffic Guard — списки сканеров"
  echo "  2  RemnaNode AntiScan — лимиты, Fail2Ban, CrowdSec, подсети РКН"
  echo "  3  Server Shield — файрвол, DDoS, SSH"
  echo "  0  Выход"
  echo
  read -r -p "Пункт: " choice < /dev/tty || exit 0
  case "$choice" in
    1) traffic_guard; pause ;;
    2) antiscan; pause ;;
    3) server_shield; pause ;;
    0) exit 0 ;;
    *) ;;
  esac
done
