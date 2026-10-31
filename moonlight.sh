#!/bin/bash
# Moonlight Security — меню. Защиты включаются только своими пунктами.
set -u
export LANG=C.UTF-8 LC_ALL=C.UTF-8

[[ $EUID -ne 0 ]] && { echo "Запуск только от root"; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
VERSION="1.1"
[[ -f "$ROOT/VERSION" ]] && VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

RESET=$'\033[0m'
BOLD=$'\033[1m'
GOLD=$'\033[38;5;179m'
CYAN=$'\033[38;5;117m'
WHITE=$'\033[38;5;255m'
GRAY=$'\033[38;5;245m'
LINE=$'\033[38;5;60m'
GREEN=$'\033[38;5;114m'
RED=$'\033[38;5;203m'
YELLOW=$'\033[38;5;221m'

W=62

pause() { read -r -p $'\n  Enter — назад  ' < /dev/tty || true; }

pad() {
  local text="$1" n
  n=$(( W - ${#text} ))
  (( n < 0 )) && n=0
  printf '%s%*s' "$text" "$n" ''
}

rule() {
  local kind="$1" fill="" i
  for (( i=0; i<W; i++ )); do fill+="─"; done
  case "$kind" in
    top) printf "${LINE}╭%s╮${RESET}\n" "$fill" ;;
    mid) printf "${LINE}├%s┤${RESET}\n" "$fill" ;;
    bot) printf "${LINE}╰%s╯${RESET}\n" "$fill" ;;
  esac
}

row() {
  printf "${LINE}│${RESET}%s${LINE}│${RESET}\n" "$(pad "$1")"
}

paint_row() {
  local plain="$1" colored="$2" n
  n=$(( W - ${#plain} ))
  (( n < 0 )) && n=0
  printf "${LINE}│${RESET}%s%*s${LINE}│${RESET}\n" "$colored" "$n" ''
}

header() {
  local subtitle="$1"
  local host ip load meta
  host="$(hostname 2>/dev/null || echo server)"
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -z "$ip" ]] && ip="нет адреса"
  load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "-")"
  meta="$host  ·  $ip  ·  load $load"
  (( ${#meta} > W - 2 )) && meta="${meta:0:$((W - 2))}"
  local left="  ●  Moonlight Security"
  local right="v${VERSION}"
  local gap=$(( W - ${#left} - ${#right} ))
  (( gap < 1 )) && gap=1
  clear
  echo
  rule top
  printf "${LINE}│${RESET}  ${GOLD}●${RESET}  ${BOLD}${WHITE}Moonlight Security${RESET}%*s${GRAY}%s${RESET}${LINE}│${RESET}\n" "$gap" "" "$right"
  paint_row "  $subtitle" "  ${GRAY}${subtitle}${RESET}"
  rule mid
  paint_row "  $meta" "  ${CYAN}${meta}${RESET}"
  rule bot
  echo
}

ask() {
  echo
  read -r -p "$(printf "  ${GOLD}▸${RESET} Пункт: ")" choice < /dev/tty || exit 0
}

usage_bar() {
  local used="$1" total="$2" pct=0 fill empty i bar=""
  [[ "${total:-0}" -gt 0 ]] && pct=$(( used * 100 / total ))
  (( pct > 100 )) && pct=100
  fill=$(( pct * 18 / 100 ))
  empty=$(( 18 - fill ))
  local color="$GREEN"
  (( pct >= 75 )) && color="$YELLOW"
  (( pct >= 90 )) && color="$RED"
  for (( i=0; i<fill; i++ )); do bar+="█"; done
  printf '%b' "$color$bar$GRAY"
  for (( i=0; i<empty; i++ )); do printf '░'; done
  printf '%b %3d%%' "$RESET" "$pct"
}

node_name() {
  command -v docker >/dev/null 2>&1 || return 0
  docker ps -a --format '{{.Names}} {{.Image}}' 2>/dev/null \
    | awk 'tolower($0) ~ /remnawave\/node|remnanode/ { print $1; exit }'
}

traffic_state() {
  local n
  n="$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | awk '/Number of entries/{print $4}')"
  if [[ -n "$n" ]]; then
    printf '%s' "включён, подсетей $n"
  else
    printf '%s' "не включён"
  fi
}

traffic_guard_menu() {
  while true; do
    header "Списки сканеров"
    echo -e "  ${GOLD}1${RESET}   ${WHITE}Установка${RESET}     ${GRAY}включить блокировку сканеров${RESET}"
    echo -e "  ${GOLD}2${RESET}   ${WHITE}Проверка${RESET}      ${GRAY}состояние, логи, ручные адреса${RESET}"
    echo
    echo -e "  ${GOLD}3${RESET}   ${WHITE}Выход${RESET}"
    ask
    case "$choice" in
      1) bash "$ROOT/trafficguard/apply.sh"; pause ;;
      2) bash "$ROOT/trafficguard/manager.sh" ;;
      3) return ;;
    esac
  done
}

antiscan() {
  header "AntiScan"
  echo -e "  ${YELLOW}Меняет UFW, SSH, Fail2Ban или CrowdSec только после выбора в его меню.${RESET}"
  echo "  Неподтверждённые правила откатятся сами."
  echo "  Проверь новое SSH-подключение, затем confirm."
  echo
  bash "$ROOT/vendor/remnanode-antiscan/install.sh"
}

server_shield() {
  if command -v shield >/dev/null 2>&1 && [[ -d /opt/server-shield/modules ]]; then
    shield
    return
  fi
  header "Server Shield"
  echo -e "  ${YELLOW}Ставит UFW, Fail2Ban и может отключить вход по паролю.${RESET}"
  echo "  Запускай, только если SSH-ключ уже лежит на сервере."
  echo
  export MOONLIGHT_SHIELD_SRC="$ROOT/vendor/server-shield"
  bash "$ROOT/vendor/server-shield/install.sh"
}

show_status() {
  header "Состояние сервера"
  local mem_total mem_avail mem_used disk_total disk_used up node tg bbr
  mem_total="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
  mem_avail="$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
  mem_used=$(( mem_total - mem_avail ))
  read -r disk_used disk_total < <(df -P / | awk 'NR==2 {print $3, $2}')
  up="$(uptime -p 2>/dev/null || true)"
  [[ -z "$up" ]] && up="$(uptime | sed 's/.*up /up /; s/, *[0-9]* user.*//')"
  node="$(node_name)"
  tg="$(traffic_state)"
  bbr="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "-")"

  printf "  ${GRAY}%-12s${RESET}%s\n" "Время" "$up"
  printf "  ${GRAY}%-12s${RESET}" "Память"
  usage_bar "$mem_used" "$mem_total"
  printf "   %s / %s МБ\n" "$(( mem_used / 1024 ))" "$(( mem_total / 1024 ))"
  printf "  ${GRAY}%-12s${RESET}" "Диск"
  usage_bar "$disk_used" "$disk_total"
  printf "   %s / %s ГБ\n" "$(( disk_used / 1024 / 1024 ))" "$(( disk_total / 1024 / 1024 ))"
  echo
  printf "  ${GRAY}%-12s${RESET}%s\n" "Сканеры" "$tg"
  printf "  ${GRAY}%-12s${RESET}%s\n" "TCP" "$bbr"
  if [[ -n "$node" ]]; then
    local st
    st="$(docker inspect -f '{{.State.Status}}' "$node" 2>/dev/null || echo "нет данных")"
    printf "  ${GRAY}%-12s${RESET}%s  %s\n" "Нода" "$node" "$st"
  else
    printf "  ${GRAY}%-12s${RESET}%s\n" "Нода" "контейнер не найден"
  fi
  echo
  echo -e "  ${GRAY}Слушает${RESET}"
  ss -lntu 2>/dev/null | awk 'NR==1 || /LISTEN|UNCONN/' | head -n 16 | sed 's/^/  /'
  pause
}

node_menu() {
  while true; do
    local name
    name="$(node_name)"
    header "Нода"
    if [[ -z "$name" ]]; then
      echo "  Контейнер Remnawave Node не найден."
      pause
      return
    fi
    local st
    st="$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo "-")"
    echo -e "  ${GRAY}Контейнер${RESET}   ${WHITE}$name${RESET}   ${CYAN}$st${RESET}"
    echo
    echo -e "  ${GOLD}1${RESET}   ${WHITE}Контейнеры${RESET}"
    echo -e "  ${GOLD}2${RESET}   ${WHITE}Логи${RESET}          ${GRAY}последние 50 строк${RESET}"
    echo -e "  ${GOLD}3${RESET}   ${WHITE}Перезапуск${RESET}"
    echo
    echo -e "  ${GOLD}0${RESET}   ${WHITE}Назад${RESET}"
    ask
    case "$choice" in
      1)
        echo
        docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
        pause
        ;;
      2)
        echo
        docker logs --tail 50 "$name" 2>&1
        pause
        ;;
      3)
        echo
        read -r -p "  Перезапустить $name? [y/N]: " yes < /dev/tty || true
        if [[ "$yes" == "y" || "$yes" == "Y" ]]; then
          docker restart "$name"
          echo "  Готово."
        else
          echo "  Оставлен как есть."
        fi
        pause
        ;;
      0) return ;;
    esac
  done
}

update_moonlight() {
  local url="https://github.com/SetFire11/moonlight-security.git"
  local saved="" tmp=""
  header "Обновление"
  echo "  Скачиваю свежую версию..."
  case "$ROOT" in
    /|/usr|/usr/*|/bin|/sbin|/etc|/etc/*|/var|/var/*|/opt|/home|/root)
      echo "  Обновление остановлено: неожиданный каталог $ROOT"
      return 1
      ;;
  esac
  [[ -f "$ROOT/moonlight.sh" && -f "$ROOT/install.sh" ]] || {
    echo "  Каталог не похож на Moonlight Security: $ROOT"
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
    echo "  Не удалось скачать обновление."
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
  echo "  Обновление установлено. Меню откроется заново."
  pause
  exec bash "$ROOT/moonlight.sh"
}

while true; do
  header "Три защиты, каждая своим пунктом"
  echo -e "  ${GOLD}1${RESET}   ${WHITE}Traffic Guard${RESET}    ${GRAY}списки сканеров${RESET}"
  echo -e "  ${GOLD}2${RESET}   ${WHITE}AntiScan${RESET}         ${GRAY}лимиты, Fail2Ban, CrowdSec, РКН${RESET}"
  echo -e "  ${GOLD}3${RESET}   ${WHITE}Server Shield${RESET}    ${GRAY}файрвол, DDoS, SSH${RESET}"
  echo
  echo -e "  ${GOLD}4${RESET}   ${WHITE}Статус${RESET}           ${GRAY}память, диск, порты, нода${RESET}"
  echo -e "  ${GOLD}5${RESET}   ${WHITE}Нода${RESET}             ${GRAY}контейнеры, логи, перезапуск${RESET}"
  echo -e "  ${GOLD}6${RESET}   ${WHITE}Обновление${RESET}       ${GRAY}свежая версия${RESET}"
  echo
  echo -e "  ${GOLD}0${RESET}   ${WHITE}Выход${RESET}"
  ask
  case "$choice" in
    1) traffic_guard_menu ;;
    2) antiscan; pause ;;
    3) server_shield; pause ;;
    4) show_status ;;
    5) node_menu ;;
    6) update_moonlight; pause ;;
    0) exit 0 ;;
  esac
done
