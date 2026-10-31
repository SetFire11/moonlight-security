#!/bin/bash
# Moonlight Security — меню. Защиты включаются только своими пунктами.
set -u
export LANG=C.UTF-8 LC_ALL=C.UTF-8

[[ $EUID -ne 0 ]] && { echo "Запуск только от root"; exit 1; }

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib/ui.sh
source "$ROOT/lib/ui.sh"
ui_init

pause() { ui_pause; }
header() { ui_screen "$1"; }
ask() { ui_ask; }

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

cpu_percent() {
  local t1="" i1="" t2="" i2="" dt di
  read -r t1 i1 < <(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat 2>/dev/null || true)
  [[ -z "${t1:-}" ]] && { printf '0'; return; }
  sleep 0.15
  read -r t2 i2 < <(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat 2>/dev/null || true)
  [[ -z "${t2:-}" ]] && { printf '0'; return; }
  dt=$(( t2 - t1 ))
  di=$(( i2 - i1 ))
  if (( dt > 0 )); then
    printf '%s' $(( (dt - di) * 100 / dt ))
  else
    printf '0'
  fi
}

cpu_cores_label() {
  local n="${1:-1}"
  case "$n" in
    1) printf '1 ядро' ;;
    2|3|4) printf '%s ядра' "$n" ;;
    *) printf '%s ядер' "$n" ;;
  esac
}

read_cpu() {
  CPU_PCT="$(cpu_percent)"
  CPU_CORES="$(cpu_cores_label "$(nproc 2>/dev/null || echo 1)")"
}

home_board() {
  local os up ip load mem_total mem_avail mem_used disk_total disk_used
  local mem_pct=0 disk_pct=0 tg node node_line
  os="$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-Linux}")"
  [[ -z "$os" ]] && os="Linux"
  up="$(uptime -p 2>/dev/null || true)"
  [[ -z "$up" ]] && up="$(uptime 2>/dev/null | sed 's/.*up /up /; s/, *[0-9]* user.*//')"
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -z "$ip" ]] && ip="нет адреса"
  load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "-")"
  mem_total="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
  mem_avail="$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
  mem_used=$(( mem_total - mem_avail ))
  read -r disk_used disk_total < <(df -P / | awk 'NR==2 {print $3, $2}')
  [[ "${mem_total:-0}" -gt 0 ]] && mem_pct=$(( mem_used * 100 / mem_total ))
  [[ "${disk_total:-0}" -gt 0 ]] && disk_pct=$(( disk_used * 100 / disk_total ))
  tg="$(traffic_state)"
  node="$(node_name)"
  node_line="контейнер не найден"
  if [[ -n "$node" ]]; then
    local st
    st="$(docker inspect -f '{{.State.Status}}' "$node" 2>/dev/null || echo "нет данных")"
    node_line="$node · $st"
  fi
  echo
  ui_frame_open "СЕРВЕР"
  ui_fact "ОС" "$os"
  ui_fact "Аптайм" "$up"
  ui_fact "Адрес" "$ip"
  ui_fact "Load" "$load"
  ui_frame_close
  ui_frame_open "ЖЕЛЕЗО"
  ui_bar "CPU" "${CPU_PCT:-0}" "${CPU_CORES:-}"
  ui_bar "Память" "$mem_pct" "$(( mem_used / 1024 )) / $(( mem_total / 1024 )) МБ"
  ui_bar "Диск" "$disk_pct" "$(( disk_used / 1024 / 1024 )) / $(( disk_total / 1024 / 1024 )) ГБ"
  ui_frame_close
  ui_frame_open "СЕЙЧАС"
  ui_fact "Сканеры" "$tg"
  ui_fact "Нода" "$node_line"
  ui_frame_close
}

traffic_guard_menu() {
  while true; do
    header "Списки сканеров"
    ui_section "ДЕЙСТВИЯ"
    ui_item 1 "Установка" "нужен включённый UFW" green
    ui_item 2 "Проверка" "состояние, логи, адреса" cyan
    echo
    ui_item 3 "Выход" "назад в главное меню" gray
    ask
    case "$choice" in
      1) bash "$ROOT/trafficguard/apply.sh"; pause ;;
      2) bash "$ROOT/trafficguard/manager.sh" ;;
      3) return ;;
    esac
  done
}

antiscan() {
  bash "$ROOT/vendor/remnanode-antiscan/install.sh"
}

server_shield() {
  if command -v shield >/dev/null 2>&1 && [[ -d /opt/server-shield/modules ]]; then
    shield
    return
  fi
  while true; do
    header "Server Shield"
    echo
    ui_frame_open "ВНИМАНИЕ"
    ui_row "Ставит UFW, Fail2Ban и может отключить вход по паролю."
    ui_row "Запускай, только если SSH-ключ уже лежит на сервере."
    ui_frame_close
    ui_section "ДЕЙСТВИЯ"
    ui_item 1 "Установка" "мастер файрвола" green
    echo
    ui_item 0 "Назад" "в главное меню" gray
    ask
    case "$choice" in
      1)
        export MOONLIGHT_SHIELD_SRC="$ROOT/vendor/server-shield"
        bash "$ROOT/vendor/server-shield/install.sh"
        return
        ;;
      0) return ;;
    esac
  done
}

show_status() {
  read_cpu
  header "Состояние сервера"
  local mem_total mem_avail mem_used disk_total disk_used up load node tg bbr line
  mem_total="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
  mem_avail="$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
  mem_used=$(( mem_total - mem_avail ))
  read -r disk_used disk_total < <(df -P / | awk 'NR==2 {print $3, $2}')
  up="$(uptime -p 2>/dev/null || true)"
  [[ -z "$up" ]] && up="$(uptime | sed 's/.*up /up /; s/, *[0-9]* user.*//')"
  load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "-")"
  node="$(node_name)"
  tg="$(traffic_state)"
  bbr="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "-")"

  local mem_pct=0 disk_pct=0 node_line="контейнер не найден"
  [[ "$mem_total" -gt 0 ]] && mem_pct=$(( mem_used * 100 / mem_total ))
  [[ "$disk_total" -gt 0 ]] && disk_pct=$(( disk_used * 100 / disk_total ))
  if [[ -n "$node" ]]; then
    local st
    st="$(docker inspect -f '{{.State.Status}}' "$node" 2>/dev/null || echo "нет данных")"
    node_line="$node  $st"
  fi
  echo
  ui_frame_open "СЕРВЕР"
  ui_fact "Время" "$up"
  ui_fact "Load" "$load"
  ui_fact "TCP" "$bbr"
  ui_frame_close
  ui_frame_open "ЖЕЛЕЗО"
  ui_bar "CPU" "${CPU_PCT:-0}" "${CPU_CORES:-}"
  ui_bar "Память" "$mem_pct" "$(( mem_used / 1024 )) / $(( mem_total / 1024 )) МБ"
  ui_bar "Диск" "$disk_pct" "$(( disk_used / 1024 / 1024 )) / $(( disk_total / 1024 / 1024 )) ГБ"
  ui_frame_close
  ui_frame_open "ЗАЩИТА"
  ui_fact "Сканеры" "$tg"
  ui_fact "Нода" "$node_line"
  ui_frame_close
  ui_frame_open "СЛУШАЕТ"
  while IFS= read -r line; do
    ui_row "$line"
  done < <(ss -lntu 2>/dev/null | awk 'NR>1 && /LISTEN|UNCONN/ {print}' | head -n 12)
  ui_frame_close
  pause
}

node_menu() {
  while true; do
    local name
    name="$(node_name)"
    header "Нода"
    if [[ -z "$name" ]]; then
      echo
      ui_frame_open "НОДА"
      ui_row "Контейнер Remnawave Node не найден."
      ui_frame_close
      pause
      return
    fi
    local st
    st="$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo "-")"
    echo
    ui_frame_open "НОДА"
    ui_fact "Контейнер" "$name"
    ui_fact "Состояние" "$st"
    ui_frame_close
    ui_item 1 "Контейнеры" "все контейнеры на сервере"
    ui_item 2 "Логи" "последние 50 строк"
    ui_item 3 "Перезапуск" "спросит подтверждение"
    ui_rule
    ui_item 0 "Назад" ""
    ui_close
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
  read_cpu
  header "Три защиты, каждая своим пунктом"
  home_board
  ui_section "ЗАЩИТА"
  ui_item 1 "Traffic Guard" "списки сканеров" gold
  ui_item 2 "AntiScan" "лимиты, Fail2Ban, CrowdSec, РКН" cyan
  ui_item 3 "Server Shield" "файрвол, DDoS, SSH" green
  ui_section "СЕРВИС"
  ui_item 4 "Статус" "память, диск, порты, нода" yellow
  ui_item 5 "Нода" "контейнеры, логи, перезапуск" yellow
  ui_item 6 "Обновление" "свежая версия" yellow
  echo
  ui_item 0 "Выход" "" gray
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
