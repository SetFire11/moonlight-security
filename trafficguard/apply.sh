#!/bin/bash
# Traffic Guard: свежие списки и включение блокировки сканеров.
# iptables-persistent не ставится, если уже есть ufw: пакет снимает ufw.
set -u
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo "Запуск только от root"; exit 1; }

# Если пакет ufw есть, блокировка вешается в ufw-before-input и молчит, пока UFW выключен.
if command -v ufw >/dev/null 2>&1; then
  ufw_status="$(ufw status 2>/dev/null | awk '/^Status:/{print $2}')"
  if [[ "$ufw_status" != "active" ]]; then
    echo "  Остановка: для Traffic Guard UFW должен быть включён."
    echo "  Сначала: ufw allow OpenSSH && ufw enable"
    exit 1
  fi
fi

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LIST_DIR="$ROOT/lists"
DEST="/opt/trafficguard/lists"
EXCLUDE="${EXCLUDE_FILE:-$ROOT/exclude.list}"
SOURCES=(government_networks.list antiscanner.list skipa.list)

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y ipset iptables rsyslog python3
if ! command -v ufw >/dev/null; then
  if ! dpkg -s iptables-persistent >/dev/null 2>&1; then
    echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
    echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
    apt-get install -y iptables-persistent netfilter-persistent
  fi
fi
systemctl enable --now rsyslog >/dev/null 2>&1 || true

install -m 755 "$ROOT/traffic-guard" /usr/local/bin/traffic-guard
ln -sfn "$ROOT/manager.sh" /opt/trafficguard-manager.sh
ln -sfn "$ROOT/manager.sh" /usr/local/bin/rknpidor
mkdir -p "$DEST" "$LIST_DIR"

echo "  Локальные списки."
cp -a "$LIST_DIR/." "$DEST/"
merged="$(mktemp)"
for name in "${SOURCES[@]}"; do
  [[ -f "$DEST/$name" ]] || continue
  grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$' "$DEST/$name" >> "$merged" || true
  grep -E '^[0-9a-fA-F:]*:[0-9a-fA-F:]+(/[0-9]{1,3})?$' "$DEST/$name" >> "$merged" || true
done
sort -u "$merged" > "$DEST/scanners.list"
rm -f "$merged"
cp -f "$DEST/scanners.list" "$LIST_DIR/scanners.list"

if [[ -f "$EXCLUDE" ]]; then
  ex="$(mktemp)"
  grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$' "$EXCLUDE" > "$ex" || true
  grep -E '^[0-9a-fA-F:]*:[0-9a-fA-F:]+(/[0-9]{1,3})?$' "$EXCLUDE" >> "$ex" || true
  if [[ -s "$ex" ]]; then
    grep -vxF -f "$ex" "$DEST/scanners.list" > "$DEST/scanners.list.tmp" || true
    mv "$DEST/scanners.list.tmp" "$DEST/scanners.list"
    echo "  Исключения: $EXCLUDE"
  fi
  rm -f "$ex"
fi

count="$(wc -l < "$DEST/scanners.list" | tr -d ' ')"
echo "  Подсетей в списке: $count"

python3 -m http.server 8765 --bind 127.0.0.1 --directory "$DEST" >/tmp/tg-http.log 2>&1 &
hpid=$!
sleep 0.5
set +e
traffic-guard full -u "http://127.0.0.1:8765/scanners.list" --enable-logging
rc=$?
set -e
kill "$hpid" 2>/dev/null || true
wait "$hpid" 2>/dev/null || true
if [[ "$rc" -ne 0 ]]; then
  echo "  traffic-guard завершился с кодом $rc"
  exit "$rc"
fi
echo "  Traffic Guard включён."
traffic-guard --version 2>/dev/null || true
