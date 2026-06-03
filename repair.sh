#!/bin/bash
# ============================================================
#  OXware Repair Script — repair.sh
#  Otomatik tanı ve onarım — tüm hata senaryoları
#  Version: 3.0
# ============================================================
# Kullanım:
#   sudo bash repair.sh                   → tam onarım
#   sudo bash repair.sh --restore-network → kırık bridge geri al
#   sudo bash repair.sh --remove-hardening → kernel hardening kaldır
#   sudo bash repair.sh --reset-credentials → admin şifresi sıfırla
#   sudo bash repair.sh --clean-disk      → disk doluysa temizle
#   sudo bash repair.sh --fix-apparmor    → AppArmor oxware engeli kaldır
#   sudo bash repair.sh --diagnose        → sadece tanı, değişiklik yok
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }
step()  { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BOLD}  $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
info()  { echo -e "    ${CYAN}→${NC} $1"; }
ok()    { echo -e "    ${GREEN}✓${NC} $1"; }
fail()  { echo -e "    ${RED}✗${NC} $1"; }

[[ $EUID -ne 0 ]] && { echo "Root gerekli: sudo bash repair.sh"; exit 1; }

INSTALL_DIR="/opt/oxware"
APP_DIR="${INSTALL_DIR}/oxware"
VENV_DIR="${INSTALL_DIR}/venv"
CONFIG_DIR="/etc/oxware"
LOG_DIR="/var/log/oxware"
DATA_DIR="/var/lib/oxware"
DROPIN_DIR="/etc/systemd/system/oxware.service.d"
WEB_PORT=8006
REPAIR_LOG="$LOG_DIR/repair-$(date +%Y%m%d-%H%M%S).log"

# ── Mode flags ────────────────────────────────────────────────
MODE_RESTORE_NETWORK=0
MODE_REMOVE_HARDENING=0
MODE_RESET_CREDENTIALS=0
MODE_CLEAN_DISK=0
MODE_FIX_APPARMOR=0
MODE_DIAGNOSE=0

for arg in "$@"; do
  case "$arg" in
    --restore-network)   MODE_RESTORE_NETWORK=1 ;;
    --remove-hardening)  MODE_REMOVE_HARDENING=1 ;;
    --reset-credentials) MODE_RESET_CREDENTIALS=1 ;;
    --clean-disk)        MODE_CLEAN_DISK=1 ;;
    --fix-apparmor)      MODE_FIX_APPARMOR=1 ;;
    --diagnose)          MODE_DIAGNOSE=1 ;;
    --help|-h)
      echo "OXware Repair Script v3.0"
      echo ""
      echo "Usage: sudo bash repair.sh [mode]"
      echo ""
      echo "  (no args)              Full repair — fixes all detected issues"
      echo "  --restore-network      Remove broken bridge, restore original network"
      echo "  --remove-hardening     Remove kernel hardening drop-in (fixes 226/NAMESPACE)"
      echo "  --reset-credentials    Reset admin username/password"
      echo "  --clean-disk           Clean logs/temp files (use when disk full)"
      echo "  --fix-apparmor         Disable AppArmor profile for oxware"
      echo "  --diagnose             Diagnose only, no changes"
      exit 0 ;;
  esac
done

mkdir -p "$LOG_DIR"
exec > >(tee -a "$REPAIR_LOG") 2>&1

echo ""
echo -e "${BOLD}  OXware Onarım Scripti v3.0${NC}"
echo -e "  Sistem: $(hostname) | $(date '+%Y-%m-%d %H:%M')"
echo -e "  Log: $REPAIR_LOG"
echo ""

# ════════════════════════════════════════════════════════════════════
#  SPECIAL MODES — run and exit
# ════════════════════════════════════════════════════════════════════

# ── DIAGNOSE only ────────────────────────────────────────────────────
if [[ $MODE_DIAGNOSE -eq 1 ]]; then
  step "Tanı Raporu (değişiklik yapılmıyor)"

  # Servis durumu
  if systemctl is-active --quiet oxware; then
    ok "oxware.service: çalışıyor"
  else
    fail "oxware.service: çalışmıyor"
    FAIL_REASON=$(systemctl show oxware --property=Result --value 2>/dev/null)
    info "Sonuç: $FAIL_REASON"
    journalctl -u oxware -n 5 --no-pager 2>/dev/null | sed 's/^/    /'
  fi

  # Hardening drop-in
  if [[ -f "$DROPIN_DIR/hardening.conf" ]]; then
    warn "Hardening drop-in mevcut: $DROPIN_DIR/hardening.conf"
    # Check if it caused NAMESPACE error
    if journalctl -u oxware -n 20 --no-pager 2>/dev/null | grep -q "NAMESPACE\|226"; then
      fail "226/NAMESPACE hatası tespit edildi — hardening drop-in neden olmuş olabilir"
      info "Çözüm: sudo bash repair.sh --remove-hardening"
    fi
  fi

  # AppArmor
  if command -v aa-status &>/dev/null; then
    if aa-status 2>/dev/null | grep -q "oxware"; then
      warn "AppArmor oxware profilini yönetiyor"
      aa-status 2>/dev/null | grep "oxware" | sed 's/^/    /'
    fi
  fi

  # Disk kullanımı
  DF=$(df -h / 2>/dev/null | awk 'NR==2{print $5" "($4)}')
  USE=$(echo "$DF" | awk '{print $1}' | tr -d '%')
  info "Disk kullanımı: $DF"
  [[ "$USE" -gt 90 ]] && fail "Disk dolmak üzere! sudo bash repair.sh --clean-disk"

  # Port 8006
  if ss -tlnp 2>/dev/null | grep -q ":8006"; then
    ok "Port 8006 dinleniyor"
  else
    fail "Port 8006 dinlenmiyor"
  fi

  # libvirtd
  systemctl is-active --quiet libvirtd && ok "libvirtd: çalışıyor" || fail "libvirtd: çalışmıyor"

  # KVM
  [[ -e /dev/kvm ]] && ok "/dev/kvm mevcut" || fail "/dev/kvm yok — KVM desteklenmiyor"

  # SSL
  [[ -f "$CONFIG_DIR/ssl/oxware.crt" ]] && ok "SSL sertifikası mevcut" || fail "SSL sertifikası yok"

  # Python venv
  [[ -f "$VENV_DIR/bin/python3" ]] && ok "Python venv mevcut" || fail "Python venv yok"

  echo ""
  exit 0
fi

# ── RESTORE NETWORK ───────────────────────────────────────────────────
if [[ $MODE_RESTORE_NETWORK -eq 1 ]] || [[ "${1:-}" == "--restore-network" ]]; then
  warn "═══════════════════════════════════════════════════════"
  warn "🛟 NETWORK RESTORE — kırık bridge config siliniyor"
  warn "═══════════════════════════════════════════════════════"

  [[ -f /etc/netplan/60-oxware-bridge.yaml ]] && \
    rm -f /etc/netplan/60-oxware-bridge.yaml && log "OXware bridge config silindi"

  LATEST_BAK=$(ls -t /etc/netplan.bak.* 2>/dev/null | head -1)
  if [[ -n "$LATEST_BAK" ]] && [[ -d "$LATEST_BAK" ]]; then
    cp -r "$LATEST_BAK"/*.yaml /etc/netplan/ 2>/dev/null && \
      log "Eski netplan config geri yüklendi: $LATEST_BAK" || \
      warn "Backup geri yüklenemedi"
  else
    warn "Netplan backup bulunamadı"
  fi

  ip link show oxbr0 &>/dev/null && { ip link set oxbr0 down; ip link delete oxbr0; log "oxbr0 kaldırıldı"; }
  timeout 30 netplan try --timeout 120 </dev/null && log "Ağ geri yüklendi ✓" || netplan apply
  log "Network restore tamamlandı."
  exit 0
fi

# ── REMOVE HARDENING ──────────────────────────────────────────────────
if [[ $MODE_REMOVE_HARDENING -eq 1 ]]; then
  step "Kernel Hardening Kaldırılıyor"

  if [[ -f "$DROPIN_DIR/hardening.conf" ]]; then
    cp "$DROPIN_DIR/hardening.conf" "$DROPIN_DIR/hardening.conf.removed.$(date +%s)" 2>/dev/null || true
    rm -f "$DROPIN_DIR/hardening.conf"
    log "Hardening drop-in kaldırıldı (backup tutuldu)"
  else
    info "Hardening drop-in zaten yok"
  fi

  # Remove AppArmor profile if loaded
  AAPROF="/etc/apparmor.d/opt.oxware.backend.app"
  if [[ -f "$AAPROF" ]] && command -v apparmor_parser &>/dev/null; then
    apparmor_parser -R "$AAPROF" 2>/dev/null || true
    log "AppArmor profili kaldırıldı"
  fi

  systemctl daemon-reload
  systemctl restart oxware
  sleep 3
  systemctl is-active --quiet oxware && log "oxware.service başlatıldı ✓" || \
    err "Servis hâlâ başlamıyor — journalctl -u oxware -n 30"
  exit 0
fi

# ── RESET CREDENTIALS ─────────────────────────────────────────────────
if [[ $MODE_RESET_CREDENTIALS -eq 1 ]]; then
  step "Admin Kimlik Sıfırlama"
  warn "Bu işlem admin kullanıcısı ve şifresini sıfırlar!"

  read -rp "  Yeni kullanıcı adı [admin]: " NEW_USER
  NEW_USER="${NEW_USER:-admin}"
  read -rsp "  Yeni şifre: " NEW_PASS; echo
  [[ -z "$NEW_PASS" ]] && { err "Şifre boş olamaz"; exit 1; }

  # Write password reset file
  RESET_FILE="/etc/oxware/.passwd_reset"
  cat > "$RESET_FILE" << RESET
USERNAME=${NEW_USER}
PASSWORD=${NEW_PASS}
RESET
  chmod 600 "$RESET_FILE"
  chown root:root "$RESET_FILE"
  log "Şifre sıfırlama dosyası yazıldı: $RESET_FILE"

  # Restart service to apply
  systemctl restart oxware 2>/dev/null || true
  sleep 3
  [[ -f "$RESET_FILE" ]] && warn "Reset dosyası henüz uygulanmadı — servis başlamamış olabilir" || \
    log "Kimlik bilgileri güncellendi ✓"
  info "Giriş: https://$(hostname -I | awk '{print $1}'):${WEB_PORT} — ${NEW_USER}"
  exit 0
fi

# ── CLEAN DISK ────────────────────────────────────────────────────────
if [[ $MODE_CLEAN_DISK -eq 1 ]]; then
  step "Disk Temizleme"
  BEFORE=$(df -h / | awk 'NR==2{print $4}')

  # Rotate logs
  find "$LOG_DIR" -name "*.log" -size +100M -exec truncate -s 10M {} \; 2>/dev/null
  find "$LOG_DIR" -name "repair-*.log" -mtime +7 -delete 2>/dev/null
  info "OXware log dosyaları döndürüldü"

  # systemd journal
  journalctl --vacuum-size=200M 2>/dev/null
  journalctl --vacuum-time=7d   2>/dev/null
  info "systemd journal temizlendi"

  # APT cache
  apt-get clean -qq 2>/dev/null || true
  info "APT cache temizlendi"

  # /tmp old files
  find /tmp -mtime +1 -not -path "/tmp/.X*" -delete 2>/dev/null || true
  info "/tmp temizlendi"

  # Cloud-init logs
  find /var/log/cloud-init* -delete 2>/dev/null || true

  # Orphan ISO cloud-init seeds
  find "${DATA_DIR}/isos" -name "ci-*.iso" -o -name "seed-*.iso" 2>/dev/null | while read -r f; do
    warn "Cloud-init ISO bulundu: $f — siliyor..."
    rm -f "$f"
  done

  AFTER=$(df -h / | awk 'NR==2{print $4}')
  log "Disk temizlendi. Serbest alan: $BEFORE → $AFTER"
  exit 0
fi

# ── FIX APPARMOR ──────────────────────────────────────────────────────
if [[ $MODE_FIX_APPARMOR -eq 1 ]]; then
  step "AppArmor Profili Devre Dışı"
  AAPROF="/etc/apparmor.d/opt.oxware.backend.app"
  if [[ -f "$AAPROF" ]]; then
    apparmor_parser -R "$AAPROF" 2>/dev/null || true
    mv "$AAPROF" "${AAPROF}.disabled.$(date +%s)"
    log "AppArmor profili devre dışı bırakıldı"
  else
    info "OXware AppArmor profili yok"
  fi
  systemctl restart oxware 2>/dev/null || true
  sleep 3
  systemctl is-active --quiet oxware && log "Servis başlatıldı ✓" || err "Servis hâlâ başlamıyor"
  exit 0
fi

# ════════════════════════════════════════════════════════════════════
#  FULL REPAIR MODE
# ════════════════════════════════════════════════════════════════════

export DEBIAN_FRONTEND=noninteractive

# ── 0. Otomatik tanı — kritik hatalar ────────────────────────────────
step "Otomatik Tanı"

_SVC_RESULT=$(systemctl show oxware --property=Result --value 2>/dev/null || echo "unknown")
_JOURNAL=$(journalctl -u oxware -n 20 --no-pager 2>/dev/null || echo "")

# 226/NAMESPACE — hardening drop-in hatası
if echo "$_JOURNAL" | grep -qE "226/NAMESPACE|Failed to set up mount namespace"; then
  warn "226/NAMESPACE hatası tespit edildi — hardening drop-in neden oluyor"
  if [[ -f "$DROPIN_DIR/hardening.conf" ]]; then
    cp "$DROPIN_DIR/hardening.conf" "$DROPIN_DIR/hardening.conf.bak.$(date +%s)" 2>/dev/null || true
    rm -f "$DROPIN_DIR/hardening.conf"
    systemctl daemon-reload
    log "Hardening drop-in kaldırıldı (backup tutuldu) — devam ediyor"
  fi
fi

# AppArmor engeli
if echo "$_JOURNAL" | grep -qE "apparmor.*denied|Permission denied.*apparmor"; then
  warn "AppArmor engeli tespit edildi"
  AAPROF="/etc/apparmor.d/opt.oxware.backend.app"
  if [[ -f "$AAPROF" ]] && command -v apparmor_parser &>/dev/null; then
    apparmor_parser -R "$AAPROF" 2>/dev/null || true
    warn "AppArmor profili geçici olarak kaldırıldı — düzeltin: bash repair.sh --fix-apparmor"
  fi
fi

# Port çakışması
if echo "$_JOURNAL" | grep -qE "Address already in use|OSError.*8006"; then
  warn "Port 8006 çakışması tespit edildi"
  CONFLICTING_PID=$(ss -tlnp 2>/dev/null | grep ":8006" | grep -oP 'pid=\K[0-9]+' | head -1)
  if [[ -n "$CONFLICTING_PID" ]]; then
    CONFLICTING_CMD=$(ps -p "$CONFLICTING_PID" -o comm= 2>/dev/null)
    if [[ "$CONFLICTING_CMD" != "python3" ]] && [[ -n "$CONFLICTING_CMD" ]]; then
      warn "Port 8006'yı tutan süreç: PID=$CONFLICTING_PID ($CONFLICTING_CMD) — öldürüyor..."
      kill "$CONFLICTING_PID" 2>/dev/null || true
      log "Çakışan süreç sonlandırıldı"
    fi
  fi
fi

# Disk dolu
DISK_USE=$(df / 2>/dev/null | awk 'NR==2{print $5}' | tr -d '%')
if [[ "${DISK_USE:-0}" -gt 95 ]]; then
  warn "Disk %${DISK_USE} dolu — otomatik temizlik yapılıyor..."
  find "$LOG_DIR" -name "*.log" -size +100M -exec truncate -s 5M {} \; 2>/dev/null
  journalctl --vacuum-size=100M 2>/dev/null || true
  apt-get clean -qq 2>/dev/null || true
  find /tmp -mtime +1 -delete 2>/dev/null || true
  log "Disk temizlendi — yeni kullanım: $(df -h / | awk 'NR==2{print $5}')"
fi

# Bozuk JSON config dosyaları
for jf in "$DATA_DIR"/*.json "$CONFIG_DIR"/*.json; do
  [[ -f "$jf" ]] || continue
  python3 -c "import json; json.load(open('$jf'))" 2>/dev/null || {
    warn "Bozuk JSON: $jf — backup alınıp sıfırlanıyor"
    cp "$jf" "${jf}.corrupt.$(date +%s)" 2>/dev/null || true
    echo '{}' > "$jf"
  }
done

log "Otomatik tanı tamamlandı"

# ── 1. SSH Onarımı ───────────────────────────────────────────
step "SSH Onarımı"
systemctl enable ssh 2>/dev/null || systemctl enable openssh-server 2>/dev/null || true
systemctl start  ssh 2>/dev/null || systemctl start  openssh-server 2>/dev/null || true

SSHD="/etc/ssh/sshd_config"
if [[ -f "$SSHD" ]]; then
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/'               "$SSHD"
  sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD"
  sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/'     "$SSHD"
  systemctl restart ssh 2>/dev/null || systemctl restart openssh-server 2>/dev/null || true
  log "SSH yapılandırması düzeltildi"
else
  warn "sshd_config bulunamadı"
fi

# ── 2. Hostname Onarımı ──────────────────────────────────────
step "Hostname Onarımı"
CURRENT_HOST=$(hostname)
if [[ "$CURRENT_HOST" == "localhost" || "$CURRENT_HOST" == "localhost.localdomain" || -z "$CURRENT_HOST" ]]; then
  HOST_IP=$(hostname -I | awk '{print $1}')
  NEW_HOST="oxware-$(echo "$HOST_IP" | tr '.' '-')"
  hostnamectl set-hostname "$NEW_HOST"
  CURRENT_HOST="$NEW_HOST"
  log "Hostname güncellendi: $CURRENT_HOST"
fi
HOST_IP=$(hostname -I | awk '{print $1}')
grep -q "^${HOST_IP}" /etc/hosts 2>/dev/null || \
  echo "${HOST_IP}  ${CURRENT_HOST}" >> /etc/hosts
sed -i "s/^127\.0\.1\.1.*/127.0.1.1  ${CURRENT_HOST}/" /etc/hosts
grep -q "127.0.1.1" /etc/hosts || echo "127.0.1.1  ${CURRENT_HOST}" >> /etc/hosts

[[ -d /etc/cloud/cloud.cfg.d ]] && cat > /etc/cloud/cloud.cfg.d/99_hostname.cfg << 'EOF'
preserve_hostname: true
manage_etc_hosts: false
EOF
log "Hostname: $CURRENT_HOST"

# ── 3. Güvenlik Duvarı ───────────────────────────────────────
step "Güvenlik Duvarı (UFW)"
if command -v update-alternatives &>/dev/null && command -v iptables-legacy &>/dev/null 2>/dev/null; then
  update-alternatives --set iptables  /usr/sbin/iptables-legacy  2>/dev/null || true
  update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
  log "iptables → iptables-legacy"
fi

if command -v ufw &>/dev/null; then
  ufw --force reset       >/dev/null 2>&1 || true
  ufw default deny  incoming >/dev/null 2>&1
  ufw default allow outgoing >/dev/null 2>&1
  ufw allow 22/tcp    comment "SSH"        >/dev/null 2>&1
  ufw allow 80/tcp    comment "HTTP"       >/dev/null 2>&1
  ufw allow 443/tcp   comment "HTTPS"      >/dev/null 2>&1
  ufw allow 8006/tcp  comment "OXware UI"  >/dev/null 2>&1
  ufw allow 5900:5999/tcp comment "VNC"    >/dev/null 2>&1
  ufw allow 6080/tcp  comment "noVNC WS"   >/dev/null 2>&1
  ufw allow 16509/tcp comment "libvirt"    >/dev/null 2>&1
  systemctl enable ufw 2>/dev/null || true
  ufw --force enable >/dev/null 2>&1
  log "UFW: SSH(22), HTTP(80), HTTPS(443), OXware(8006), VNC(5900-5999), noVNC(6080), libvirt(16509)"
else
  warn "ufw bulunamadı"
fi

# ── 4. KVM / Ağ Onarımı ─────────────────────────────────────
step "KVM ve Ağ Onarımı"
for mod in kvm kvm_intel kvm_amd br_netfilter; do
  modprobe "$mod" 2>/dev/null || true
done
for mod in kvm kvm_intel kvm_amd; do
  grep -qx "$mod" /etc/modules 2>/dev/null || echo "$mod" >> /etc/modules
done
grep -q "br_netfilter" /etc/modules-load.d/*.conf 2>/dev/null || \
  echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf
[[ -e /dev/kvm ]] && log "KVM: /dev/kvm mevcut" || warn "/dev/kvm yok — sunucu KVM destekliyor mu?"

# Yavaş başlatma kaynağını devre dışı bırak
systemctl disable NetworkManager-wait-online.service 2>/dev/null || true
systemctl mask    NetworkManager-wait-online.service 2>/dev/null || true
mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d/
cat > /etc/systemd/system/systemd-networkd-wait-online.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/lib/systemd/systemd-networkd-wait-online --timeout=10
EOF

# libvirt
systemctl enable --now libvirtd 2>/dev/null || true
sleep 2
for i in $(seq 1 8); do virsh list >/dev/null 2>&1 && break; sleep 2; done
virsh net-autostart default 2>/dev/null || true
virsh net-start default    2>/dev/null || true
log "libvirtd ve varsayılan ağ başlatıldı"

# ── 5. Dizin ve İzinler ──────────────────────────────────────
step "Dizin ve İzinler"
[[ ! -f "${APP_DIR}/backend/app.py" ]] && {
  err "Uygulama bulunamadı: ${APP_DIR}/backend/app.py"
  info "Git pull yapın: cd ${INSTALL_DIR} && git pull"
}

mkdir -p "$LOG_DIR" "$CONFIG_DIR/ssl" "$DATA_DIR"/{isos,disks,backups,templates}
chown root:root "$CONFIG_DIR" && chmod 700 "$CONFIG_DIR"
chmod 755 "$LOG_DIR" "$DATA_DIR"
# Fix broken permissions
find "$CONFIG_DIR" -name "*.key" -exec chmod 600 {} \; 2>/dev/null || true
find "$CONFIG_DIR" -name "*.conf" -exec chmod 600 {} \; 2>/dev/null || true
log "Dizinler ve izinler düzeltildi"

# ── 6. Sistem Paketleri ──────────────────────────────────────
step "Sistem Paketleri"
apt-get update -qq 2>/dev/null || true
apt-get install -y -qq --no-install-recommends \
  pkg-config gcc build-essential \
  python3 python3-pip python3-venv python3-dev python3-libvirt \
  libvirt-dev libvirt-daemon-system libvirt-clients \
  openssl ca-certificates novnc websockify \
  qemu-kvm qemu-utils \
  certbot python3-certbot \
  apparmor apparmor-utils 2>/dev/null || warn "Bazı paketler kurulamadı"
log "Sistem paketleri hazır"

# ── 7. Python venv ───────────────────────────────────────────
step "Python Sanal Ortamı"

# Broken venv check
if [[ -d "$VENV_DIR" ]] && ! "$VENV_DIR/bin/python3" -c "import flask" 2>/dev/null; then
  warn "Bozuk venv tespit edildi — yeniden oluşturuluyor..."
  rm -rf "$VENV_DIR"
fi

[[ ! -f "${VENV_DIR}/bin/python3" ]] && {
  python3 -m venv "$VENV_DIR"
  log "Venv oluşturuldu"
}

source "${VENV_DIR}/bin/activate"
pip install --upgrade pip -q

if [[ -f "${APP_DIR}/backend/requirements.txt" ]]; then
  pip install -r "${APP_DIR}/backend/requirements.txt" -q
else
  pip install -q flask flask-jwt-extended flask-socketio eventlet cryptography \
    paramiko psutil requests flask-cors
fi
pip install -q cryptography libvirt-python
deactivate
log "Python paketleri kuruldu"

# ── 8. Config dosyası ────────────────────────────────────────
step "Konfigürasyon"
if [[ ! -f "$CONFIG_DIR/oxware.conf" ]]; then
  SECRET=$(openssl rand -hex 32)
  cat > "$CONFIG_DIR/oxware.conf" << CONF
[server]
host       = 0.0.0.0
port       = ${WEB_PORT}
ssl        = true
ssl_cert   = ${CONFIG_DIR}/ssl/oxware.crt
ssl_key    = ${CONFIG_DIR}/ssl/oxware.key
secret_key = ${SECRET}
novnc_dir  = /usr/share/novnc

[storage]
data_dir     = ${DATA_DIR}
iso_dir      = ${DATA_DIR}/isos
disk_dir     = ${DATA_DIR}/disks
backup_dir   = ${DATA_DIR}/backups
template_dir = ${DATA_DIR}/templates

[vnc]
start_port     = 5900
end_port       = 5999
websocket_port = 6080

[libvirt]
uri = qemu:///system

[logging]
log_dir = ${LOG_DIR}
level   = INFO
CONF
  chmod 600 "$CONFIG_DIR/oxware.conf"
  log "Config oluşturuldu"
else
  log "Config mevcut"
fi

# ── 9. SSL sertifikası ───────────────────────────────────────
step "SSL Sertifikası"
HOST_IP=$(hostname -I | awk '{print $1}')
HOSTNAME_VAL=$(hostname -f 2>/dev/null || hostname)

# Expired cert check
CERT_EXPIRED=0
if [[ -f "$CONFIG_DIR/ssl/oxware.crt" ]]; then
  openssl x509 -checkend 86400 -noout -in "$CONFIG_DIR/ssl/oxware.crt" 2>/dev/null || CERT_EXPIRED=1
fi

if [[ ! -f "$CONFIG_DIR/ssl/oxware.crt" || ! -f "$CONFIG_DIR/ssl/oxware.key" || $CERT_EXPIRED -eq 1 ]]; then
  [[ $CERT_EXPIRED -eq 1 ]] && warn "SSL sertifikası süresi dolmuş — yenileniyor..."
  mkdir -p "$CONFIG_DIR/ssl"
  openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
    -keyout "$CONFIG_DIR/ssl/oxware.key" \
    -out    "$CONFIG_DIR/ssl/oxware.crt" \
    -subj "/C=TR/O=OXware/CN=$HOSTNAME_VAL" \
    -addext "subjectAltName=IP:${HOST_IP},DNS:${HOSTNAME_VAL},DNS:localhost" 2>/dev/null
  chmod 600 "$CONFIG_DIR/ssl/oxware.key"
  log "SSL sertifikası oluşturuldu (10 yıl)"
else
  EXPIRY=$(openssl x509 -enddate -noout -in "$CONFIG_DIR/ssl/oxware.crt" 2>/dev/null | cut -d= -f2)
  log "SSL sertifikası mevcut (son geçerlilik: $EXPIRY)"
fi

# ── 10. Systemd Servisi (tam rebuild — hardening drop-in TUTULUR eğer çalışıyorsa) ─
step "Systemd Servisi"

# Rebuild main service file (clean baseline)
cat > /etc/systemd/system/oxware.service << SERVICE
[Unit]
Description=OXware Hypervisor Management Service
Documentation=https://github.com/ShinnAsukha/oxware-hypervisor
After=network-online.target libvirtd.service libvirt-guests.service
Wants=network-online.target libvirtd.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=${APP_DIR}
Environment=OXWARE_CONFIG=${CONFIG_DIR}/oxware.conf
Environment=PYTHONUNBUFFERED=1
ExecStartPre=/bin/bash -c 'mkdir -p ${LOG_DIR} ${DATA_DIR}/{isos,disks,backups,templates} ${CONFIG_DIR} && chown root:root ${CONFIG_DIR} && chmod 700 ${CONFIG_DIR}'
ExecStartPre=/bin/bash -c 'for i in \$(seq 1 15); do virsh list >/dev/null 2>&1 && break; sleep 2; done; true'
ExecStartPre=/bin/bash -c 'virsh net-list --all 2>/dev/null | grep -q default && virsh net-start default 2>/dev/null || true'
ExecStart=${VENV_DIR}/bin/python3 ${APP_DIR}/backend/app.py
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
StartLimitIntervalSec=120
StartLimitBurst=5
TimeoutStartSec=60
TimeoutStopSec=30
KillMode=mixed
StandardOutput=append:${LOG_DIR}/oxware.log
StandardError=append:${LOG_DIR}/oxware-error.log
SyslogIdentifier=oxware
NoNewPrivileges=false
PrivateTmp=false

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable oxware
log "Servis dosyası güncellendi"

# ── 10b. Bridge ─────────────────────────────────────────────
step "Host Bridge (oxbr0)"
PIFACE=$(ip route show default 2>/dev/null \
  | awk '/^default/{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[[ -z "$PIFACE" ]] && PIFACE="ens160"

if ip link show oxbr0 &>/dev/null; then
  ip link set "$PIFACE" master oxbr0 2>/dev/null || true
  log "oxbr0 mevcut"
elif [[ "${OXWARE_REPAIR_BRIDGE:-0}" == "1" ]]; then
  warn "Bridge kurulacak — SSH geçici düşebilir (netplan try 120s)"
  sleep 3
  PIP=$(ip addr show "$PIFACE" 2>/dev/null | awk '/inet /{print $2; exit}')
  PGW=$(ip route show default 2>/dev/null | awk '/^default/{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}')
  if [[ -n "$PIP" && -n "$PGW" ]]; then
    cp -r /etc/netplan "/etc/netplan.bak.$(date +%s)" 2>/dev/null || true
    NP="/etc/netplan/60-oxware-bridge.yaml"
    cat > "$NP" << NETPLANCFG
network:
  version: 2
  ethernets:
    ${PIFACE}:
      dhcp4: false
  bridges:
    oxbr0:
      interfaces: [${PIFACE}]
      dhcp4: false
      addresses: [${PIP}]
      routes:
        - to: default
          via: ${PGW}
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
      parameters:
        stp: false
        forward-delay: 0
NETPLANCFG
    chmod 600 "$NP"
    timeout 30 netplan try --timeout 120 </dev/null && log "oxbr0 oluşturuldu ✓" || \
      warn "oxbr0 başarısız — eski config geri yüklendi"
  else
    warn "IP/gateway tespit edilemedi"
  fi
else
  info "oxbr0 yok — bridge kurmak: sudo OXWARE_REPAIR_BRIDGE=1 bash repair.sh"
fi

# libvirt oxbridge
if ! virsh net-info oxbridge &>/dev/null; then
  cat > /tmp/_oxbridge_net.xml << 'LIBVIRTNET'
<network><name>oxbridge</name><forward mode='bridge'/><bridge name='oxbr0'/></network>
LIBVIRTNET
  virsh net-define /tmp/_oxbridge_net.xml 2>/dev/null && \
    virsh net-autostart oxbridge 2>/dev/null && \
    virsh net-start oxbridge 2>/dev/null && \
    log "libvirt oxbridge kayıt edildi" || true
  rm -f /tmp/_oxbridge_net.xml
else
  virsh net-start oxbridge 2>/dev/null || true
fi

# ── 10c. MOTD ────────────────────────────────────────────────
mkdir -p /etc/update-motd.d
cat > /etc/update-motd.d/99-oxware << 'MOTDSCRIPT'
#!/bin/bash
BOLD='\033[1m'; RED='\033[0;31m'; RESET='\033[0m'; LINE='\033[0;90m'
HOST=$(hostname -f 2>/dev/null || hostname)
DATE=$(date '+%Y-%m-%d %H:%M:%S %Z')
printf "\n${LINE}──────────────────────────────────────────────────────────────${RESET}\n"
printf "  ${BOLD}OXware Hypervisor${RESET}  |  %s  |  %s\n" "$HOST" "$DATE"
printf "${LINE}──────────────────────────────────────────────────────────────${RESET}\n"
printf "\n  ${RED}NOTICE:${RESET} Restricted system. All sessions monitored and logged.\n"
printf "\n  ${BOLD}Support:${RESET} https://github.com/ShinnAsukha/oxware-hypervisor\n\n"
printf "${LINE}──────────────────────────────────────────────────────────────${RESET}\n\n"
MOTDSCRIPT
chmod +x /etc/update-motd.d/99-oxware
find /etc/update-motd.d -type f ! -name "99-oxware" -exec chmod -x {} \;
systemctl disable motd-news.service motd-news.timer 2>/dev/null || true
echo "" > /etc/motd 2>/dev/null || true

# ── 10d. AdaOS uyumluluk ─────────────────────────────────────
[[ -d /etc/adaos && ! -e /etc/oxware ]]    && ln -s /etc/adaos    /etc/oxware    2>/dev/null || true
[[ -d /var/lib/adaos && ! -e /var/lib/oxware ]] && ln -s /var/lib/adaos /var/lib/oxware 2>/dev/null || true
[[ -d /etc/oxware ]] && grep -rl "AdaOS" /etc/oxware/ 2>/dev/null | \
  xargs -r sed -i 's/AdaOS/OXware/g'

# ── 11. noVNC / Websockify ───────────────────────────────────
step "noVNC / Websockify"
if ! command -v websockify &>/dev/null; then
  apt-get install -y -qq novnc websockify 2>/dev/null || \
    pip install websockify -q 2>/dev/null || \
    warn "websockify kurulamadı"
else
  log "websockify mevcut: $(websockify --version 2>&1 | head -1)"
fi
NOVNC_PATHS=("/usr/share/novnc" "/usr/share/noVNC" "/opt/novnc")
for p in "${NOVNC_PATHS[@]}"; do [[ -d "$p" ]] && { log "noVNC: $p"; break; }; done

# ── 12. Servis Başlat ─────────────────────────────────────────
step "Servis Başlatılıyor"
systemctl stop oxware 2>/dev/null || true
sleep 2

# Final check: remove hardening if still failing
systemctl start oxware
sleep 5

if ! systemctl is-active --quiet oxware; then
  FAIL=$(systemctl show oxware --property=Result --value 2>/dev/null)
  JOUT=$(journalctl -u oxware -n 5 --no-pager 2>/dev/null)

  if echo "$JOUT" | grep -qE "226/NAMESPACE|NAMESPACE"; then
    warn "226/NAMESPACE — hardening drop-in kaldırılıyor..."
    rm -f "$DROPIN_DIR/hardening.conf"
    systemctl daemon-reload
    systemctl start oxware
    sleep 5
  elif echo "$JOUT" | grep -qE "apparmor.*denied|Permission denied"; then
    warn "AppArmor engeli — profil kaldırılıyor..."
    apparmor_parser -R /etc/apparmor.d/opt.oxware.backend.app 2>/dev/null || true
    systemctl start oxware
    sleep 5
  elif echo "$JOUT" | grep -qE "Address already in use|OSError.*8006"; then
    warn "Port çakışması — port 8006 temizleniyor..."
    fuser -k 8006/tcp 2>/dev/null || true
    systemctl start oxware
    sleep 5
  elif echo "$JOUT" | grep -qE "ModuleNotFoundError|ImportError|No module named"; then
    warn "Python modül hatası — venv yeniden kuruluyor..."
    rm -rf "$VENV_DIR"
    python3 -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    if [[ -f "${APP_DIR}/backend/requirements.txt" ]]; then
      pip install -r "${APP_DIR}/backend/requirements.txt" -q
    else
      pip install -q flask flask-jwt-extended flask-socketio eventlet cryptography paramiko psutil requests flask-cors libvirt-python
    fi
    deactivate
    systemctl start oxware
    sleep 5
  fi
fi

# ── Özet ─────────────────────────────────────────────────────
echo ""
HOST_IP=$(hostname -I | awk '{print $1}')
if systemctl is-active --quiet oxware; then
  echo -e "${GREEN}╔══════════════════════════════════════════════════════╗"
  echo -e "║         OXware Onarım Tamamlandı! ✓                ║"
  echo -e "╠══════════════════════════════════════════════════════╣"
  echo -e "║${NC}                                                      ${GREEN}║"
  echo -e "║${NC}  🌐 Web UI  : ${CYAN}https://${HOST_IP}:${WEB_PORT}${NC}$(printf '%*s' $((18-${#HOST_IP})) '')${GREEN}║"
  echo -e "║${NC}  🔐 SSH     : ${CYAN}ssh root@${HOST_IP}${NC}$(printf '%*s' $((22-${#HOST_IP})) '')${GREEN}║"
  echo -e "║${NC}  📋 Log     : ${CYAN}journalctl -u oxware -f${NC}              ${GREEN}║"
  echo -e "║${NC}  🔎 Tanı    : ${CYAN}bash repair.sh --diagnose${NC}            ${GREEN}║"
  echo -e "║${NC}                                                      ${GREEN}║"
  echo -e "╚══════════════════════════════════════════════════════╝${NC}"
else
  echo ""
  err "Servis başlatılamadı!"
  echo ""
  journalctl -u oxware -n 20 --no-pager 2>/dev/null
  echo ""
  echo -e "${YELLOW}Önerilen adımlar:${NC}"
  echo "  1. bash repair.sh --diagnose"
  echo "  2. bash repair.sh --remove-hardening  # 226/NAMESPACE için"
  echo "  3. bash repair.sh --fix-apparmor       # AppArmor engeli için"
  echo "  4. bash repair.sh --clean-disk         # Disk doluysa"
  echo "  5. bash repair.sh --reset-credentials  # Şifre sıfırlama"
  echo "  6. journalctl -u oxware -n 50"
  echo "  7. cat $LOG_DIR/oxware-error.log"
fi

echo ""
echo -e "${BOLD}Tüm modlar:${NC}  bash repair.sh --help"
echo -e "Repair log: $REPAIR_LOG"
