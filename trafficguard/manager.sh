#!/bin/bash
set -u

# --- ЦВЕТА ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

MANUAL_FILE="/opt/trafficguard-manual.list"
ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=../lib/ui.sh
source "$ROOT/../lib/ui.sh"
ui_init

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}Запуск только от root!${NC}"; exit 1; }
}

check_firewall_safety() {
    echo "  Проверяю файрвол."
    if command -v ufw >/dev/null; then
        UFW_STATUS=$(ufw status | grep "Status" | awk '{print $2}')
        UFW_RULES=$(ufw show added 2>/dev/null)
        if [[ "$UFW_STATUS" != "active" ]]; then
            echo "  Остановка: для Traffic Guard UFW должен быть включён."
            echo "  Сначала: ufw allow OpenSSH && ufw enable"
            exit 1
        fi
        if [[ "$UFW_RULES" != *"22"* ]] && [[ "$UFW_RULES" != *"SSH"* ]] && [[ "$UFW_RULES" != *"OpenSSH"* ]]; then
            echo "  Остановка: в UFW нет правила SSH."
            echo "  Сначала: ufw allow OpenSSH"
            exit 1
        fi
    else
        if ! dpkg -l | grep -q netfilter-persistent; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq && \
            DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent netfilter-persistent
        fi
    fi
}

scanner_set_for() {
    local ip="$1"
    if [[ "$ip" == *:* ]]; then
        printf '%s\n' "SCANNERS-BLOCK-V6"
    else
        printf '%s\n' "SCANNERS-BLOCK-V4"
    fi
}

valid_address() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]] && return 0
    [[ "$ip" =~ ^[0-9a-fA-F:]*:[0-9a-fA-F:]+(/[0-9]{1,3})?$ ]] && return 0
    return 1
}

save_ipset() {
    local tmp
    tmp="$(mktemp /etc/ipset.conf.XXXXXX)" || return 1
    if ipset save > "$tmp"; then
        chmod 644 "$tmp"
        mv "$tmp" /etc/ipset.conf
    else
        rm -f "$tmp"
        return 1
    fi
}

restore_manual_bans() {
    [[ -s "$MANUAL_FILE" ]] || return 0
    local ip set
    while IFS= read -r ip || [[ -n "$ip" ]]; do
        ip="${ip//$'\r'/}"
        [[ -z "$ip" || "$ip" == \#* ]] && continue
        valid_address "$ip" || continue
        set="$(scanner_set_for "$ip")"
        ipset add "$set" "$ip" -exist 2>/dev/null || true
    done < "$MANUAL_FILE"
    save_ipset || true
}

fix_logging() {
    local conf="/etc/rsyslog.d/10-iptables-scanners.conf"
    local agg="/usr/local/bin/antiscan-aggregate-logs.sh"
    local csv="/var/log/iptables-scanners-aggregate.csv"
    local tmp unit="/etc/systemd/system/trafficguard-manual.service"
    local changed

    if ! command -v whois >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y whois
    fi

    changed="$(python3 - "$conf" "$agg" <<'PY'
import sys
from pathlib import Path

changed = False
conf = Path(sys.argv[1])
if conf.is_file():
    raw = conf.read_text(encoding="utf-8", errors="replace")
    lines = raw.splitlines()
    out = []
    for i, line in enumerate(lines):
        out.append(line)
        nxt = lines[i + 1] if i + 1 < len(lines) else ""
        if line.startswith(":msg, contains,") and nxt.strip() != "& stop":
            out.append("& stop")
    text = "\n".join(out) + "\n"
    if raw != text:
        conf.write_text(text, encoding="utf-8")
        changed = True

agg = Path(sys.argv[2])
if agg.is_file():
    script = agg.read_text(encoding="utf-8", errors="replace")
    skip = '        case "$ip" in 0.0.0.0|::|::1) continue ;; esac\n'
    needle = "while read cnt ip; do\n"
    if skip not in script:
        agg.write_text(script.replace(needle, needle + skip), encoding="utf-8")
print("changed" if changed else "same")
PY
)"
    if [[ "$changed" == *changed* && -f "$conf" ]]; then
        systemctl try-restart rsyslog >/dev/null 2>&1 || true
    fi

    if [[ -f "$csv" ]]; then
        tmp="$(mktemp)"
        awk -F'|' 'NR == 1 || ($2 != "0.0.0.0" && $2 != "::" && $2 != "::1")' "$csv" > "$tmp"
        mv "$tmp" "$csv"
    fi

    if [[ -f /tmp/antiscan-whois-cache.txt ]]; then
        tmp="$(mktemp)"
        grep -v '|UNKNOWN|UNKNOWN$' /tmp/antiscan-whois-cache.txt > "$tmp" || true
        mv "$tmp" /tmp/antiscan-whois-cache.txt
    fi

    cat > "$unit" <<'EOF'
[Unit]
Description=Traffic Guard manual bans
After=antiscan-ipset-restore.service
Wants=antiscan-ipset-restore.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/rknpidor restore-manual

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable trafficguard-manual.service >/dev/null 2>&1 || true
}

uninstall_process() {
    ui_screen "Удаление"
    echo
    trap 'echo; echo "  Отмена."; return' INT
    read -r -p "$(printf "  ${GOLD}${BOLD}▸${RESET} ${WHITE}Снять блокировку?${RESET} ${GRAY}[y/N]${RESET}: ")" confirm < /dev/tty
    trap 'exit 0' INT

    [[ "$confirm" != "y" ]] && return

    systemctl disable --now trafficguard-manual.service >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/trafficguard-manual.service
    systemctl daemon-reload >/dev/null 2>&1 || true

    # Удаляем файлы менеджера
    rm -f /usr/local/bin/rknpidor /opt/trafficguard-manager.sh "$MANUAL_FILE"

    # Используем встроенный uninstall traffic-guard (чистит UFW, ipset, iptables, systemd, rsyslog)
    if command -v traffic-guard >/dev/null 2>&1; then
        traffic-guard uninstall --yes
    else
        # Fallback: ручная чистка (если бинарник уже удалён)
        systemctl stop antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null
        systemctl disable antiscan-aggregate.timer antiscan-aggregate.service 2>/dev/null
        rm -f /usr/local/bin/traffic-guard /usr/local/bin/antiscan-aggregate-logs.sh
        rm -f /etc/systemd/system/antiscan-*
        rm -f /etc/rsyslog.d/10-iptables-scanners.conf /etc/logrotate.d/iptables-scanners

        iptables -D INPUT -j SCANNERS-BLOCK 2>/dev/null
        iptables -F SCANNERS-BLOCK 2>/dev/null
        iptables -X SCANNERS-BLOCK 2>/dev/null
        ipset flush SCANNERS-BLOCK-V4 2>/dev/null
        ipset destroy SCANNERS-BLOCK-V4 2>/dev/null
        ipset flush SCANNERS-BLOCK-V6 2>/dev/null
        ipset destroy SCANNERS-BLOCK-V6 2>/dev/null

        # Чистим UFW (причина бага: правила оставались в before.rules)
        sed -i '/SCANNERS-BLOCK/d' /etc/ufw/before.rules 2>/dev/null
        sed -i '/SCANNERS-BLOCK/d' /etc/ufw/before6.rules 2>/dev/null
        ufw reload 2>/dev/null
    fi

    systemctl restart rsyslog 2>/dev/null
    echo
    echo "  Блокировка снята."
    exit 0
}

# --- 🧪 УПРАВЛЕНИЕ IP ---
manage_test_ip() {
    # Создаем файл списка, если нет
    touch "$MANUAL_FILE"
    trap 'continue' INT
    
    while true; do
        ui_screen "Адреса" "Ручная блокировка"
        ui_open
        ui_item 1 "Забанить" "добавить адрес в блок"
        ui_item 2 "Разбанить" "убрать из ручного списка"
        ui_rule
        ui_item 0 "Назад" ""
        ui_close
        ui_ask
        action="$choice"

        case $action in
            1)
                echo
                trap 'echo; echo "  Отмена."; sleep 1; continue' INT
                read -r -p "$(printf "  ${GOLD}${BOLD}▸${RESET} ${WHITE}Адрес для бана:${RESET} ")" ip < /dev/tty
                [[ -z "$ip" ]] && continue
                if ! valid_address "$ip"; then
                    echo "  Это не адрес."
                    ui_pause
                    continue
                fi

                set_name="$(scanner_set_for "$ip")"
                OUTPUT=$(ipset add "$set_name" "$ip" 2>&1)
                rc=$?
                if [ "$rc" -eq 0 ]; then
                    echo "  ${ip} добавлен в блок."
                    if ! grep -Fxq "$ip" "$MANUAL_FILE"; then
                        printf '%s\n' "$ip" >> "$MANUAL_FILE"
                    fi
                    save_ipset || echo "  В файл набора не записалось."
                else
                    echo "  Не вышло: $OUTPUT"
                fi
                ui_pause
                ;;
            2)
                echo
                ui_frame_open "РУЧНЫЕ"
                if [ ! -s "$MANUAL_FILE" ]; then
                    ui_row "Список пуст"
                    MANUAL_IPS=()
                else
                    mapfile -t MANUAL_IPS < "$MANUAL_FILE"
                    i=1
                    for ip in "${MANUAL_IPS[@]}"; do
                        ui_row "$i  $ip"
                        i=$((i + 1))
                    done
                fi
                ui_frame_close
                echo
                trap 'echo; echo "  Отмена."; sleep 1; continue' INT
                read -r -p "$(printf "  ${GOLD}${BOLD}▸${RESET} ${WHITE}Номер или адрес:${RESET} ")" input < /dev/tty
                [[ -z "$input" ]] && continue
                
                TARGET_IP=""
                
                # Проверяем, число это или IP
                if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -le "${#MANUAL_IPS[@]}" ] && [ "$input" -gt 0 ]; then
                    # Это номер из списка (массив начинается с 0, ввод с 1)
                    INDEX=$((input-1))
                    TARGET_IP="${MANUAL_IPS[$INDEX]}"
                else
                    # Это вероятно IP
                    TARGET_IP="$input"
                fi
                
                TARGET_IP="${TARGET_IP//$'\r'/}"
                [[ -z "$TARGET_IP" ]] && continue
                echo "  Снимаю ${TARGET_IP}."

                set_name="$(scanner_set_for "$TARGET_IP")"
                OUTPUT=$(ipset del "$set_name" "$TARGET_IP" 2>&1)
                rc=$?
                tmp_manual="$(mktemp)"
                grep -vxF "$TARGET_IP" "$MANUAL_FILE" > "$tmp_manual" || true
                mv "$tmp_manual" "$MANUAL_FILE"

                if [ "$rc" -eq 0 ]; then
                    save_ipset || echo "  В файл набора не записалось."
                    echo "  Адрес снят."
                else
                    echo "  Из блока не ушёл: $OUTPUT"
                    echo "  Из ручного списка убран."
                fi
                ui_pause
                ;;
            0) 
                trap 'exit 0' INT
                return 
                ;;
            *) ;;
        esac
    done
}

update_lists() {
    ui_screen "Списки"
    echo
    echo "  Перечитываю файлы."
    bash "$ROOT/apply.sh"
    echo "  Готово."
    sleep 2
}

install_process() {
    trap 'exit 1' INT
    ui_screen "Установка"
    check_firewall_safety
    bash "$ROOT/apply.sh"

    if [ $? -ne 0 ]; then
        echo
        echo "  Установка остановилась."
        exit 1
    fi

    mkdir -p /var/log
    touch /var/log/iptables-scanners-{ipv4,ipv6}.log
    LOG_GROUP="syslog"; getent group adm >/dev/null && LOG_GROUP="adm"
    chown syslog:$LOG_GROUP /var/log/iptables-scanners-*.log
    chmod 640 /var/log/iptables-scanners-*.log
    
    # Создаем файл для ручных банов, если нет
    touch "$MANUAL_FILE"
    
    systemctl restart rsyslog
    systemctl restart antiscan-aggregate.service 2>/dev/null || true
    systemctl restart antiscan-aggregate.timer
    
    echo
    echo "  Установка завершена."
    sleep 2
}

view_log() {
    local file=$1
    ui_screen "Лог"
    echo
    printf "  ${GRAY}Ctrl+C — назад${RESET}\n"
    echo
    trap ':' INT
    tail -f "$file"
    trap 'exit 0' INT
}

# LOG is rate-limited, so only the DROP rules give the real number.
drop_count() {
    "$1" -nvxL "$2" 2>/dev/null | awk '$3 == "DROP" && /match-set/ { s += $1 } END { print s + 0 }'
}

show_menu() {
    trap 'exit 0' INT
    while true; do
        IPSET_CNT=$(ipset list SCANNERS-BLOCK-V4 2>/dev/null | awk '/Number of entries/{print $4}')
        [[ -z "$IPSET_CNT" ]] && IPSET_CNT="0"
        # CrowdSec and the AntiScan RKN chain sit before Traffic Guard in INPUT, so a packet
        # dropped by one of them never reaches the next one.
        CS_CNT=$(( $(drop_count iptables CROWDSEC_CHAIN) + $(drop_count ip6tables CROWDSEC_CHAIN) ))
        RKN_CNT=$(( $(drop_count iptables antiscan-rkn) + $(drop_count ip6tables antiscan-rkn) ))
        PKTS_CNT=$(( $(drop_count iptables SCANNERS-BLOCK) + $(drop_count ip6tables SCANNERS-BLOCK) ))
        ui_screen "Traffic Guard"
        echo
        ui_frame_open "СОСТОЯНИЕ"
        ui_fact "Подсети" "$IPSET_CNT"
        ui_fact "Отбито всего" "$(( CS_CNT + RKN_CNT + PKTS_CNT ))"
        if iptables -nL CROWDSEC_CHAIN >/dev/null 2>&1; then
            ui_fact "  CrowdSec" "$CS_CNT"
        fi
        if iptables -nL antiscan-rkn >/dev/null 2>&1; then
            ui_fact "  РКН" "$RKN_CNT"
        fi
        ui_fact "  Traffic Guard" "$PKTS_CNT"
        if (( PKTS_CNT == 0 && CS_CNT + RKN_CNT > 0 )); then
            ui_row "Traffic Guard последний: его сети ловят фильтры выше."
        fi
        ui_frame_close
        ui_section "СМОТРЕТЬ"
        ui_item 1 "Топ атак" "последние записи" cyan
        ui_item 2 "Лог IPv4" "в реальном времени" cyan
        ui_item 3 "Лог IPv6" "в реальном времени" cyan
        ui_section "СПИСКИ"
        ui_item 4 "Адреса" "бан и разбан" gold
        ui_item 5 "Обновить списки" "перечитать файлы" gold
        ui_item 6 "Переустановить" "" yellow
        ui_section "ОПАСНО"
        ui_item 7 "Удалить" "снять блокировку" red
        echo
        ui_item 0 "Выход" "" gray
        ui_ask

        case $choice in
            1)
                ui_screen "Топ атак"
                echo
                ui_frame_open "ЧАЩЕ ВСЕГО"
                if [[ -s /var/log/iptables-scanners-aggregate.csv ]]; then
                    # The aggregator keeps the header first and sorts the rest by count, highest first.
                    while IFS= read -r line; do
                        ui_row "$line"
                    done < <(head -21 /var/log/iptables-scanners-aggregate.csv)
                else
                    ui_row "Записей нет"
                fi
                ui_frame_close
                ui_pause
                ;;
            2) view_log "/var/log/iptables-scanners-ipv4.log" ;;
            3) view_log "/var/log/iptables-scanners-ipv6.log" ;;
            4) manage_test_ip ;;
            5) update_lists ;;
            6) 
                rm -f /var/log/iptables-scanners-aggregate.csv
                install_process 
                ;;
            7) uninstall_process ;;
            0) exit 0 ;;
            *) echo "Неверно"; sleep 1 ;;
        esac
    done
}

check_root
case "${1:-}" in
    install) install_process ;;
    monitor) show_menu ;;
    update) update_lists ;;
    uninstall) uninstall_process ;;
    restore-manual) restore_manual_bans ;;
    fix-logging) fix_logging ;;
    *) show_menu ;; 
esac
