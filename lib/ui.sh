#!/bin/bash
# Рамки и пункты меню Moonlight Security.

ui_init() {
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
  NC="$RESET"
  BLUE="$CYAN"
  W=64
  VERSION="${VERSION:-1.0}"
  local vf=""
  [[ -n "${ROOT:-}" && -f "$ROOT/VERSION" ]] && vf="$ROOT/VERSION"
  [[ -z "$vf" && -n "${ROOT:-}" && -f "$ROOT/../VERSION" ]] && vf="$ROOT/../VERSION"
  [[ -n "$vf" ]] && VERSION="$(tr -d '[:space:]' < "$vf")"
}

ui_fill() {
  local n="$1" s="" i
  for (( i=0; i<n; i++ )); do s+="═"; done
  printf '%s' "$s"
}

ui_pad() {
  local text="$1" width="$2" n
  n=$(( width - ${#text} ))
  (( n < 0 )) && n=0
  printf '%s%*s' "$text" "$n" ""
}

ui_box_row() {
  local plain="$1" colored="$2" n
  n=$(( W - ${#plain} ))
  (( n < 0 )) && n=0
  printf "${LINE}║${RESET}%s%*s${LINE}║${RESET}\n" "$colored" "$n" ""
}

ui_top() { printf "${LINE}╔%s╗${RESET}\n" "$(ui_fill "$W")"; }
ui_mid() { printf "${LINE}╠%s╣${RESET}\n" "$(ui_fill "$W")"; }
ui_bot() { printf "${LINE}╚%s╝${RESET}\n" "$(ui_fill "$W")"; }

ui_screen() {
  local section="$1"
  local host ip load left right gap spaces plain sec meta
  host="$(hostname 2>/dev/null || echo server)"
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -z "$ip" ]] && ip="нет адреса"
  load="$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "-")"
  left="  ●  Moonlight Security"
  right="v${VERSION} "
  gap=$(( W - ${#left} - ${#right} ))
  (( gap < 1 )) && gap=1
  spaces="$(printf '%*s' "$gap" "")"
  plain="${left}${spaces}${right}"
  sec="  ${section}"
  (( ${#sec} > W )) && sec="${sec:0:W}"
  meta="  ${host}  ·  ${ip}  ·  load ${load}"
  if (( ${#meta} > W )); then
    host="${host:0:16}"
    meta="  ${host}  ·  ${ip}  ·  load ${load}"
    (( ${#meta} > W )) && meta="${meta:0:W}"
  fi
  clear
  echo
  ui_top
  ui_box_row "$plain" "  ${GOLD}●${RESET}  ${BOLD}${WHITE}Moonlight Security${RESET}${spaces}${GRAY}${right}${RESET}"
  ui_box_row "$sec" "  ${GOLD}${section}${RESET}"
  ui_mid
  ui_box_row "$meta" "  ${CYAN}${host}${RESET}  ${GRAY}·${RESET}  ${WHITE}${ip}${RESET}  ${GRAY}·${RESET}  ${GRAY}load${RESET} ${WHITE}${load}${RESET}"
  ui_bot
}

ui_frame_open() {
  local name="$1" n
  n=$(( W - 5 - ${#name} ))
  (( n < 1 )) && n=1
  printf "${LINE}╔═${RESET}${CYAN}${BOLD}[ %s ]${RESET}${LINE}%s╗${RESET}\n" "$name" "$(ui_fill "$n")"
}

ui_frame_close() { ui_bot; }

ui_section() {
  echo
  printf "  ${CYAN}${BOLD}[ %s ]${RESET}\n" "$1"
}

ui_fact() {
  local lab value="$2" plain
  lab="$(ui_pad "$1" 16)"
  plain="  ${lab} ${value}"
  if (( ${#plain} > W )); then
    value="${value:0:$(( W - 19 ))}"
    plain="  ${lab} ${value}"
  fi
  ui_box_row "$plain" "  ${GRAY}${lab}${RESET} ${WHITE}${value}${RESET}"
}

ui_bar() {
  local label="$1" pct="$2" detail="${3:-}"
  local fill empty i bar_f="" bar_e="" color lab pcts plain
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  fill=$(( pct * 12 / 100 ))
  (( pct > 0 && fill == 0 )) && fill=1
  empty=$(( 12 - fill ))
  for (( i=0; i<fill; i++ )); do bar_f+="■"; done
  for (( i=0; i<empty; i++ )); do bar_e+="□"; done
  color="$GREEN"
  (( pct >= 70 )) && color="$YELLOW"
  (( pct >= 90 )) && color="$RED"
  lab="$(ui_pad "$label" 16)"
  printf -v pcts '%3d%%' "$pct"
  plain="  ${lab} ${pcts}  ${bar_f}${bar_e}"
  if [[ -n "$detail" && $(( ${#plain} + 2 + ${#detail} )) -gt W ]]; then
    detail=""
  fi
  local colored="  ${GRAY}${lab}${RESET} ${WHITE}${pcts}${RESET}  ${color}${bar_f}${GRAY}${bar_e}${RESET}"
  if [[ -n "$detail" ]]; then
    plain+="  ${detail}"
    colored+="  ${GRAY}${detail}${RESET}"
  fi
  ui_box_row "$plain" "$colored"
}

ui_row() {
  local text="$1" plain
  (( ${#text} > W - 2 )) && text="${text:0:$(( W - 2 ))}"
  plain="  ${text}"
  ui_box_row "$plain" "  ${GRAY}${text}${RESET}"
}

ui_note() {
  local tone="${1:-gray}" text="$2" color plain
  case "$tone" in
    ok) color="$GREEN" ;;
    warn) color="$YELLOW" ;;
    bad) color="$RED" ;;
    *) color="$GRAY" ;;
  esac
  (( ${#text} > W - 2 )) && text="${text:0:$(( W - 2 ))}"
  plain="  ${text}"
  ui_box_row "$plain" "  ${color}${text}${RESET}"
}

ui_open() { :; }
ui_rule() { echo; }
ui_close() { echo; }

ui_item() {
  local key="$1" title="$2" desc="${3:-}" tone="${4:-gold}"
  local kc="$GOLD"
  case "$tone" in
    red) kc="$RED" ;;
    cyan) kc="$CYAN" ;;
    green) kc="$GREEN" ;;
    yellow) kc="$YELLOW" ;;
    gray) kc="$GRAY" ;;
  esac
  printf "  ${kc}${BOLD}[%s]${RESET} ${WHITE}%s${RESET}\n" "$key" "$title"
  if [[ -n "$desc" ]]; then
    printf "      ${GRAY}└ %s${RESET}\n" "$desc"
  fi
}

ui_stats() {
  local ll="$1" lv="$2" rl="$3" rv="$4"
  local lw=31
  local rw=$(( W - lw - 1 ))
  local l1="  $ll" l2="  $lv" r1="  $rl" r2="  $rv"
  local n n2
  printf "${LINE}╔%s╦%s╗${RESET}\n" "$(ui_fill "$lw")" "$(ui_fill "$rw")"
  n=$(( lw - ${#l1} )); (( n < 0 )) && n=0
  n2=$(( rw - ${#r1} )); (( n2 < 0 )) && n2=0
  printf "${LINE}║${RESET}${GRAY}%s${RESET}%*s${LINE}║${RESET}${GRAY}%s${RESET}%*s${LINE}║${RESET}\n" "$l1" "$n" "" "$r1" "$n2" ""
  n=$(( lw - ${#l2} )); (( n < 0 )) && n=0
  n2=$(( rw - ${#r2} )); (( n2 < 0 )) && n2=0
  printf "${LINE}║${RESET}${GREEN}${BOLD}%s${RESET}%*s${LINE}║${RESET}${GOLD}${BOLD}%s${RESET}%*s${LINE}║${RESET}\n" "$l2" "$n" "" "$r2" "$n2" ""
  printf "${LINE}╚%s╩%s╝${RESET}\n" "$(ui_fill "$lw")" "$(ui_fill "$rw")"
}

ui_kv() {
  local label="$1" value="$2"
  local lab plain
  lab="$(ui_pad "$label" 16)"
  plain="  ${lab} : ${value}"
  if (( ${#plain} > W )); then
    value="${value:0:$(( W - 21 ))}"
    plain="  ${lab} : ${value}"
  fi
  ui_box_row "$plain" "  ${GRAY}${lab}${RESET} ${GOLD}:${RESET} ${WHITE}${value}${RESET}"
}

ui_meter() {
  local label="$1" pct="$2" detail="${3:-}"
  local fill empty i bar_f="" bar_e="" pcts lab plain
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  fill=$(( pct * 16 / 100 ))
  empty=$(( 16 - fill ))
  for (( i=0; i<fill; i++ )); do bar_f+="■"; done
  for (( i=0; i<empty; i++ )); do bar_e+="□"; done
  printf -v pcts '%3d%%' "$pct"
  lab="$(ui_pad "$label" 16)"
  plain="  ${lab} : ${bar_f}${bar_e} ${pcts}"
  [[ -n "$detail" ]] && plain+="  ${detail}"
  if (( ${#plain} > W )); then
    detail=""
    plain="  ${lab} : ${bar_f}${bar_e} ${pcts}"
  fi
  ui_box_row "$plain" "  ${GRAY}${lab}${RESET} ${GOLD}:${RESET} ${GREEN}${bar_f}${GRAY}${bar_e}${RESET} ${WHITE}${pcts}${RESET}  ${GRAY}${detail}${RESET}"
}

ui_panel_open() { ui_top; }
ui_panel_close() { ui_bot; echo; }

ui_ask() {
  echo
  read -r -p "$(printf "  ${GOLD}${BOLD}▸${RESET} ${WHITE}Пункт:${RESET} ")" choice < /dev/tty || exit 0
}

ui_pause() { read -r -p $'\n   Enter — назад  ' < /dev/tty || true; }
