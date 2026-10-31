#!/bin/bash
# Moonlight Security — отдельные пункты, без общей простыни правил.
set -u
CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo "Запуск только от root"; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

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

update_moonlight() {
  local url="https://github.com/SetFire11/moonlight-security.git"
  local saved="" tmp=""
  echo "Скачиваю обновление..."
  case "$ROOT" in
    /|/usr|/usr/*|/bin|/sbin|/etc|/etc/*|/var|/var/*|/opt|/home|/root)
      echo "Обновление остановлено: неожиданный каталог $ROOT"
      return 1
      ;;
  esac
  [[ -f "$ROOT/moonlight.sh" && -f "$ROOT/install.sh" ]] || {
    echo "Каталог не похож на Moonlight Security: $ROOT"
    return 1
  }
  if ! command -v git >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y git ca-certificates
  fi
  if [[ -f "$ROOT/trafficguard/exclude.list" ]]; then
    saved="$(mktemp)"
    cp -a "$ROOT/trafficguard/exclude.list" "$saved"
  fi
  tmp="$(mktemp -d)"
  if ! GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch main "$url" "$tmp/src"; then
    echo "Не удалось скачать обновление."
    rm -rf "$tmp"
    [[ -n "$saved" ]] && rm -f "$saved"
    return 1
  fi
  rm -rf "$ROOT"
  mkdir -p "$ROOT"
  cp -a "$tmp/src/." "$ROOT/"
  rm -rf "$tmp"
  if [[ -n "$saved" ]]; then
    mkdir -p "$ROOT/trafficguard"
    cp -a "$saved" "$ROOT/trafficguard/exclude.list"
    rm -f "$saved"
  fi
  bash "$ROOT/install.sh" || return 1
  echo
  echo "Обновление установлено. Меню откроется заново."
  pause
  exec bash "$ROOT/moonlight.sh"
}

while true; do
  clear
  echo -e "${CYAN}Moonlight Security${NC}"
  echo "Три защиты отдельно. Одним пунктом они не включаются вместе."
  echo
  echo "  1  Traffic Guard — списки сканеров"
  echo "  2  RemnaNode AntiScan — лимиты, Fail2Ban, CrowdSec, подсети РКН"
  echo "  3  Server Shield — файрвол, DDoS, SSH"
  echo "  4  Обновление"
  echo "  0  Выход"
  echo
  read -r -p "Пункт: " choice < /dev/tty || exit 0
  case "$choice" in
    1) traffic_guard; pause ;;
    2) antiscan; pause ;;
    3) server_shield; pause ;;
    4) update_moonlight; pause ;;
    0) exit 0 ;;
    *) ;;
  esac
done
