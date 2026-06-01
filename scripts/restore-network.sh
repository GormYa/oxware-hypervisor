#!/bin/bash
# OXware Network Restore — SSH koptuğunda bridge'i geri al
# Console'dan veya rescue mode'dan çalıştır:
#   curl -sSL https://raw.githubusercontent.com/ShinnAsukha/oxware-hypervisor/main/scripts/restore-network.sh | sudo bash
# Veya local: sudo bash /opt/oxware/scripts/restore-network.sh

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}Root gerekli: sudo bash $0${NC}"; exit 1; }

echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗"
echo -e "║   OXware Network Restore — Bridge'i Geri Al           ║"
echo -e "║   SSH kopmuşsa konsoldan çalıştır.                    ║"
echo -e "╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. OXware bridge config'i kaldır
if [ -f /etc/netplan/60-oxware-bridge.yaml ]; then
    rm -f /etc/netplan/60-oxware-bridge.yaml
    echo -e "${GREEN}[✓]${NC} OXware bridge config silindi"
fi

# 2. En son backup'ı bul + geri yükle
LATEST_BAK=$(ls -td /etc/netplan.bak.* 2>/dev/null | head -1)
if [ -n "$LATEST_BAK" ] && [ -d "$LATEST_BAK" ]; then
    echo -e "${CYAN}[i]${NC} Backup bulundu: $LATEST_BAK"
    # Sadece backup'taki dosyaları al (mevcutları override etme)
    for src in "$LATEST_BAK"/*.yaml; do
        [ -f "$src" ] || continue
        fname=$(basename "$src")
        # OXware bridge dosyasını atla (zaten sildik)
        [ "$fname" = "60-oxware-bridge.yaml" ] && continue
        cp "$src" "/etc/netplan/$fname"
        chmod 600 "/etc/netplan/$fname"
        echo -e "${GREEN}[✓]${NC} Geri yüklendi: /etc/netplan/$fname"
    done
else
    echo -e "${YELLOW}[!]${NC} Backup yok — minimal DHCP config oluşturuluyor"
    # Detect primary iface from /sys (route gone, can't use ip route)
    PIFACE=""
    for i in /sys/class/net/e*/operstate /sys/class/net/en*/operstate; do
        [ -f "$i" ] || continue
        ifname=$(basename "$(dirname "$i")")
        [ "$ifname" = "lo" ] && continue
        [ "$(cat "$i")" = "up" ] && PIFACE="$ifname" && break
    done
    [ -z "$PIFACE" ] && PIFACE="ens160"

    cat > /etc/netplan/01-oxware-restore.yaml << NP
network:
  version: 2
  ethernets:
    ${PIFACE}:
      dhcp4: true
      dhcp6: false
NP
    chmod 600 /etc/netplan/01-oxware-restore.yaml
    echo -e "${GREEN}[✓]${NC} Minimal DHCP config: /etc/netplan/01-oxware-restore.yaml ($PIFACE)"
fi

# 3. Bridge interface kaldır
if ip link show oxbr0 &>/dev/null 2>&1; then
    ip link set oxbr0 down 2>/dev/null || true
    ip link delete oxbr0 2>/dev/null || true
    echo -e "${GREEN}[✓]${NC} oxbr0 kaldırıldı"
fi

# 4. netplan apply (try yok — kullanıcı zaten konsoldan koşuyor, rollback gereksiz)
echo -e "${CYAN}[i]${NC} netplan apply yapılıyor..."
netplan apply 2>&1 | tail -5

sleep 3

# 5. Durum
echo ""
echo -e "${CYAN}═══════════════ Sonuç ═══════════════${NC}"
ip addr show | grep -E "^[0-9]+:|inet " | head -20
echo ""
echo -e "${GREEN}[✓]${NC} Network restore tamamlandı. SSH bağlantını dene."
echo -e "${CYAN}[i]${NC} Servisi yeniden başlat: systemctl restart oxware"
