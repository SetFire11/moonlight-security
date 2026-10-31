#!/bin/bash
# Отчёт о состоянии AntiScan. Только чтение.

set -euo pipefail
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/lib/ui.sh"
ui_init

FRAME=0
close_section() {
    [[ "$FRAME" == 1 ]] || return 0
    ui_frame_close
    FRAME=0
}
section() {
    close_section
    ui_frame_open "$1"
    FRAME=1
}
ok()   { ui_note ok "$*"; }
warn() { ui_note warn "$*"; }
bad()  { ui_note bad "$*"; }
off()  { ui_note gray "$*"; }

ui_screen "Статус защиты"
echo

section "UFW"
if [[ -f /var/lib/ufw-antiscan/pending ]]; then
    warn "Применение не подтверждено, ждёт отката"
fi

UFW_STATUS=$(LC_ALL=C ufw status 2>/dev/null | head -1 || true)
if [[ "$UFW_STATUS" == "Status: active" ]]; then
    ok "UFW включён"
elif grep -q "UFW-ANTISCAN START" /etc/ufw/before.rules 2>/dev/null; then
    bad "UFW выключен, а правила Experimental уже записаны"
else
    warn "UFW выключен. Для Basic это не мешает"
fi

if grep -q "UFW-ANTISCAN START" /etc/ufw/before.rules 2>/dev/null; then
    ok "Правила записаны в before.rules"
    if iptables -S ufw-antiscan >/dev/null 2>&1; then
        if iptables -C ufw-before-input -j ufw-antiscan >/dev/null 2>&1; then
            ok "Цепочка IPv4 подключена"
        else
            bad "Цепочка IPv4 есть, перехода к ней нет"
        fi
    else
        bad "Цепочка IPv4 не загружена"
    fi
else
    off "Experimental не установлен"
fi

section "SSH"
SSH_DROPIN=/etc/ssh/sshd_config.d/00-remnanode-antiscan.conf
if [[ -f "$SSH_DROPIN" ]]; then
    ok "Конфигурация SSH установлена"
    SSHD=$(command -v sshd 2>/dev/null || true)
    [[ -n "$SSHD" ]] || [[ ! -x /usr/sbin/sshd ]] || SSHD=/usr/sbin/sshd
    if [[ -n "$SSHD" ]]; then
        EFFECTIVE=$(LC_ALL=C "$SSHD" -T 2>/dev/null || true)
        PUBKEY=$(awk '$1=="pubkeyauthentication"{print $2}' <<< "$EFFECTIVE")
        PASSWORD=$(awk '$1=="passwordauthentication"{print $2}' <<< "$EFFECTIVE")
        KBD=$(awk '$1=="kbdinteractiveauthentication"{print $2}' <<< "$EFFECTIVE")
        ui_fact "Ключ" "${PUBKEY:-?}"
        ui_fact "Пароль" "${PASSWORD:-?}"
        ui_fact "Keyboard" "${KBD:-?}"
        [[ "$PUBKEY" == yes && "$PASSWORD" == no && "$KBD" == no ]] \
            && ok "Вход по ключу, пароль выключен" \
            || warn "SSH сейчас настроен иначе"
    else
        bad "sshd не найден"
    fi
else
    off "Basic не управляет входом по паролю"
fi

section "BBR"
BBR_SYSCTL=/etc/sysctl.d/99-remnanode-antiscan-bbr-cake.conf
IPV6_SYSCTL=/etc/sysctl.d/99-remnanode-antiscan-ipv6.conf
TCP_CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unavailable)
DEFAULT_QDISC=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unavailable)
ui_fact "TCP" "$TCP_CC"
ui_fact "Qdisc" "$DEFAULT_QDISC"
if [[ "$TCP_CC" == bbr && "$DEFAULT_QDISC" == cake ]]; then
    ok "BBR включён, CAKE выбран"
elif [[ -f "$BBR_SYSCTL" ]]; then
    bad "Файл BBR есть, рабочие значения другие"
else
    off "BBR + CAKE через AntiScan не включены"
fi
if command -v tc >/dev/null; then
    CAKE_ACTIVE=$(tc qdisc show 2>/dev/null | grep -c 'qdisc cake ' || true)
    if [[ "$CAKE_ACTIVE" -gt 0 ]]; then
        ok "CAKE уже на интерфейсах: ${CAKE_ACTIVE}"
    elif [[ "$DEFAULT_QDISC" == cake ]]; then
        warn "CAKE включится на интерфейсах после перезагрузки"
    fi
fi

if [[ -d /proc/sys/net/ipv6/conf ]]; then
    IPV6_ENABLED=0
    IPV6_DISABLED=0
    for IPV6_PATH in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
        [[ -f "$IPV6_PATH" ]] || continue
        IPV6_IFACE=${IPV6_PATH%/disable_ipv6}
        IPV6_IFACE=${IPV6_IFACE##*/}
        [[ "$IPV6_IFACE" != all && "$IPV6_IFACE" != default ]] || continue
        if [[ "$(cat "$IPV6_PATH")" == 0 ]]; then
            IPV6_ENABLED=$((IPV6_ENABLED + 1))
        else
            IPV6_DISABLED=$((IPV6_DISABLED + 1))
        fi
    done
    if [[ "$IPV6_DISABLED" == 0 ]]; then
        ok "IPv6 включён"
    elif [[ "$IPV6_ENABLED" == 0 ]]; then
        ok "IPv6 выключен"
    else
        warn "IPv6 включён на ${IPV6_ENABLED}, выключен на ${IPV6_DISABLED}"
    fi
    [[ ! -f "$IPV6_SYSCTL" ]] || ok "IPv6 держит AntiScan"
else
    warn "IPv6 нет"
fi

close_section
bash "$SCRIPT_DIR/rkn.sh" status || { section "РКН"; warn "Статус РКН не прочитался"; }

section "PORTSCAN"
RECENT_FILE=/proc/net/xt_recent/PORTSCANNERS
[[ -r "$RECENT_FILE" ]] || RECENT_FILE=/proc/net/ipt_recent/PORTSCANNERS
PORTSCAN_ENABLED=0
if iptables -S ufw-antiscan 2>/dev/null | grep -q PORTSCANNERS; then
    PORTSCAN_ENABLED=1
    if [[ ! -r "$RECENT_FILE" ]]; then
        warn "Автобан включён, таблица recent недоступна"
    else
        SCAN_COUNT=$(wc -l < "$RECENT_FILE")
        if [[ "$SCAN_COUNT" -gt 0 ]]; then
            warn "Записей recent: ${SCAN_COUNT}"
            awk '{
                for(i=1;i<=NF;i++){
                    if($i ~ /^src=/) { gsub("src=","",$i); print $i }
                }
            }' "$RECENT_FILE" 2>/dev/null | tail -10 | while IFS= read -r ip; do
                ui_note gray "$ip"
            done
        else
            ok "Активных банов нет"
        fi
    fi
else
    off "Автобан сканеров выключен"
fi

section "FAIL2BAN"
if command -v fail2ban-client &>/dev/null; then
    if systemctl is-active fail2ban &>/dev/null; then
        ok "Запущен"
        F2B_OUT=$(fail2ban-client status sshd 2>/dev/null || true)
        if [[ -n "$F2B_OUT" ]]; then
            BANNED=$(echo "$F2B_OUT" | awk '/Currently banned:/{print $NF}')
            TOTAL=$(echo "$F2B_OUT"  | awk '/Total banned/{print $NF}')
            ui_fact "Сейчас" "${BANNED:-0}"
            ui_fact "Всего" "${TOTAL:-0}"
        fi
    else
        bad "Не запущен"
    fi
else
    off "Не установлен"
fi

section "CROWDSEC"
if command -v cscli &>/dev/null; then
    if systemctl is-active crowdsec &>/dev/null; then
        ok "Агент запущен"
    else
        bad "Агент не запущен"
    fi
    if systemctl is-active crowdsec-firewall-bouncer &>/dev/null; then
        ok "Bouncer запущен"
    else
        bad "Bouncer не запущен"
    fi
    crowdsec_bans() {
        cscli decisions list "$@" -o json 2>/dev/null | python3 -c '
import json
import sys
alerts = json.load(sys.stdin) or []
bans = [d for a in alerts for d in (a.get("decisions") or [])]
print(len(bans))
for d in bans[:5]:
    value, scenario, duration = (str(d.get(k, "?")) for k in ("value", "scenario", "duration"))
    print("%s  %s (%s)" % (value, scenario, duration))
' 2>/dev/null
    }
    LOCAL_BANS=$(crowdsec_bans || true)
    if [[ -n "$LOCAL_BANS" ]]; then
        ok "Локальных банов: $(head -1 <<< "$LOCAL_BANS")"
        if [[ $(wc -l <<< "$LOCAL_BANS") -gt 1 ]]; then
            tail -n +2 <<< "$LOCAL_BANS" | while IFS= read -r line; do
                ui_note gray "$line"
            done
        fi
    else
        warn "Список решений не прочитался"
    fi
    ALL_BANS=$(crowdsec_bans -a | head -1 || true)
    [[ -z "$ALL_BANS" ]] || ui_fact "Всего" "$ALL_BANS"
else
    off "Не установлен"
fi

section "ПРАВИЛА"
got_rule=0
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    got_rule=1
    ui_note gray "$line"
done < <(LC_ALL=C ufw status numbered 2>/dev/null | sed -n '1,20p' || true)
[[ "$got_rule" == 1 ]] || warn "Правила UFW не прочитались"

section "КОМАНДЫ"
if [[ "$PORTSCAN_ENABLED" == 1 ]]; then
    ui_note gray "Снять бан: echo -<IP> > ${RECENT_FILE}"
fi
if command -v fail2ban-client >/dev/null; then
    ui_note gray "Fail2Ban: fail2ban-client set sshd unbanip <IP>"
fi
if command -v cscli >/dev/null; then
    ui_note gray "CrowdSec: cscli decisions delete --ip <IP>"
fi
ui_note gray "Откат: пункт Удалить в меню AntiScan"
close_section
echo
