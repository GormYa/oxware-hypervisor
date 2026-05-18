#!/usr/bin/env bash
# ============================================================
#  OXware Hypervisor — ISO Builder v5.0
#  Base : Debian 12 (Bookworm) Live Standard
#  Boot : getty autologin root → startx → Calamares (fullscreen)
#  Proxmox VE ile aynı mantık: desktop yok, DM yok, direkt installer
# ============================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Versiyon ──────────────────────────────────────────────────────────────────
VERSION_FILE="$SCRIPT_DIR/VERSION"
[ -f "$VERSION_FILE" ] || echo "2.0.0" > "$VERSION_FILE"
_PREV="$(cat "$VERSION_FILE" | tr -d '[:space:]')"
_MAJ="$(echo "$_PREV" | cut -d. -f1)"
_MIN="$(echo "$_PREV" | cut -d. -f2)"
_PAT="$(echo "$_PREV" | cut -d. -f3)"
_PAT=$(( _PAT + 1 ))
OXWARE_VERSION="${_MAJ}.${_MIN}.${_PAT}"
echo "$OXWARE_VERSION" > "$VERSION_FILE"

# ── Paths ─────────────────────────────────────────────────────────────────────
# Debian 12 Live Standard — masaüstü yok, sadece temel sistem
# "standard" variant ~700MB, bizim ihtiyacımıza tam uygun
DEBIAN_LIVE_URL="https://ftp.halifax.rwth-aachen.de/debian-cd/current-live/amd64/iso-hybrid/debian-live-12.10.0-amd64-standard.iso"
DEBIAN_LIVE_FALLBACK="https://mirror.init7.net/debian-cd/current-live/amd64/iso-hybrid/debian-live-12.10.0-amd64-standard.iso"
ISO_CACHE="/tmp/debian-12-live-standard-amd64.iso"
WORK_DIR="/tmp/oxware-iso-build"
SQUASHFS_ROOT="$WORK_DIR/squashfs-root"
OUTPUT_ISO="$REPO_ROOT/OXware-Hypervisor-${OXWARE_VERSION}-amd64.iso"

log()  { echo -e "${GREEN}[BUILD]${NC}  $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}   $1"; }
err()  { echo -e "${RED}[ERROR]${NC}  $1"; exit 1; }
step() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

[[ $EUID -ne 0 ]] && err "Root gerekli: sudo bash build/build-iso.sh"

# ── Bağımlılıklar ─────────────────────────────────────────────────────────────
step "Bağımlılıklar"
apt-get update -qq
apt-get install -y -qq \
    xorriso squashfs-tools wget curl \
    grub-pc-bin grub-efi-amd64-bin mtools \
    debootstrap rsync python3 \
    genisoimage syslinux-utils 2>/dev/null || true
log "OK"

# ── Disk alanı ────────────────────────────────────────────────────────────────
_FREE_KB=$(df -k "$PWD" | awk 'NR==2{print $4}')
[ "$_FREE_KB" -lt 15728640 ] && \
    err "Yetersiz disk: $(df -h "$PWD" | awk 'NR==2{print $4}'), en az 15GB gerek"
log "Disk: $(df -h "$PWD" | awk 'NR==2{print $4}') boş"

# ── Debian 12 Live ISO ────────────────────────────────────────────────────────
step "Debian 12 Live Standard ISO"
if [ -f "$ISO_CACHE" ] && [ "$(stat -c%s "$ISO_CACHE")" -gt 500000000 ]; then
    log "Cache'de mevcut: $ISO_CACHE ($(du -sh "$ISO_CACHE" | cut -f1))"
else
    log "İndiriliyor: $DEBIAN_LIVE_URL"
    wget -q --show-progress -c -O "$ISO_CACHE" "$DEBIAN_LIVE_URL" 2>/dev/null || {
        warn "Ana mirror başarısız, fallback deneniyor..."
        wget -q --show-progress -c -O "$ISO_CACHE" "$DEBIAN_LIVE_FALLBACK" \
            || err "İndirme başarısız. Manuel:\n  wget -O $ISO_CACHE $DEBIAN_LIVE_URL"
    }
fi

# ── ISO Ayıkla ────────────────────────────────────────────────────────────────
step "ISO Ayıklama"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/iso"
xorriso -osirrox on -indev "$ISO_CACHE" -extract / "$WORK_DIR/iso" 2>/dev/null \
    || err "ISO ayıklanamadı"
chmod -R u+w "$WORK_DIR/iso"
log "ISO içeriği: $(du -sh "$WORK_DIR/iso" | cut -f1)"

# Debian live squashfs: /live/filesystem.squashfs
SQUASHFS_FILE=""
for f in \
    "$WORK_DIR/iso/live/filesystem.squashfs" \
    "$WORK_DIR/iso/casper/filesystem.squashfs"; do
    [ -f "$f" ] && SQUASHFS_FILE="$f" && break
done
[ -z "$SQUASHFS_FILE" ] && err "filesystem.squashfs bulunamadı!"

# Live dizini bul (grub path için)
LIVE_DIR="$(dirname "$SQUASHFS_FILE" | sed "s|$WORK_DIR/iso||")"
log "Squashfs: $SQUASHFS_FILE ($(du -sh "$SQUASHFS_FILE" | cut -f1))"
log "Live dir: $LIVE_DIR"

# ── Squashfs Aç ───────────────────────────────────────────────────────────────
step "Squashfs Açılıyor (~5-10 dk)"
unsquashfs -d "$SQUASHFS_ROOT" "$SQUASHFS_FILE"
log "Açıldı: $(du -sh "$SQUASHFS_ROOT" | cut -f1)"

# ── Chroot: Paket Kurulum ─────────────────────────────────────────────────────
step "Chroot: Calamares + X11 Kurulum (~10 dk)"

mkdir -p "$SQUASHFS_ROOT"/{proc,sys,dev,dev/pts,run,tmp}
cp /etc/resolv.conf "$SQUASHFS_ROOT/etc/resolv.conf" 2>/dev/null || true

_umount_all() {
    for mp in dev/pts dev sys proc run; do
        umount "$SQUASHFS_ROOT/$mp" 2>/dev/null || true
    done
}
trap _umount_all EXIT

mount --bind /proc    "$SQUASHFS_ROOT/proc"
mount --bind /sys     "$SQUASHFS_ROOT/sys"
mount --bind /dev     "$SQUASHFS_ROOT/dev"
mount --bind /dev/pts "$SQUASHFS_ROOT/dev/pts"
mount --bind /run     "$SQUASHFS_ROOT/run"

chroot "$SQUASHFS_ROOT" /bin/bash << 'CHROOT'
export DEBIAN_FRONTEND=noninteractive
export LANG=C

# Debian 12 repo (backports dahil — Calamares yeni versiyonu için)
cat > /etc/apt/sources.list << 'APT'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib
deb http://security.debian.org/debian-security bookworm-security main contrib
deb http://deb.debian.org/debian bookworm-backports main contrib
APT

apt-get update -qq

# ── Minimal X11 (sadece gerekli olanlar — Proxmox gibi ağır DE yok) ───────────
apt-get install -y -qq --no-install-recommends \
    xorg \
    xserver-xorg-core \
    xserver-xorg-video-all \
    xserver-xorg-input-all \
    x11-xserver-utils \
    xinit \
    openbox \
    2>/dev/null || true

# ── Calamares (bookworm-backports'tan daha yeni versiyon al) ──────────────────
apt-get install -y -qq --no-install-recommends \
    -t bookworm-backports \
    calamares \
    calamares-data \
    2>/dev/null || \
apt-get install -y -qq --no-install-recommends \
    calamares \
    calamares-data \
    2>/dev/null || true

# ── Calamares bağımlılıkları ──────────────────────────────────────────────────
apt-get install -y -qq --no-install-recommends \
    libkpmcore12 libkpmcore-dev kpmcore \
    python3 python3-yaml python3-parted \
    parted dosfstools e2fsprogs \
    qml-module-qtquick2 \
    qml-module-qtquick-controls2 \
    qml-module-qtquick-layouts \
    libqt5qml5 libqt5quick5 \
    2>/dev/null || true

# kpmcore — partition modülü için kritik
apt-get install -y -qq --no-install-recommends \
    libkpmcore11 \
    2>/dev/null || true

# ── Disk / ağ araçları (install.py --headless için) ───────────────────────────
apt-get install -y -qq --no-install-recommends \
    debootstrap \
    util-linux \
    iproute2 \
    net-tools \
    dhcpcd5 \
    curl \
    git \
    sudo \
    2>/dev/null || true

# ── GUI / font / D-Bus araçları ───────────────────────────────────────────────
apt-get install -y -qq --no-install-recommends \
    python3-tk \
    fonts-ubuntu \
    fonts-noto-core \
    fontconfig \
    xterm \
    dbus \
    dbus-x11 \
    libdbus-1-3 \
    policykit-1 \
    udisks2 \
    xserver-xorg-video-qxl \
    xserver-xorg-video-vmware \
    spice-vdagent \
    libqt5network5 \
    libqt5svg5 \
    2>/dev/null || true
fc-cache -f 2>/dev/null || true

# ── Türkçe locale ─────────────────────────────────────────────────────────────
apt-get install -y -qq locales 2>/dev/null || true
sed -i 's/# tr_TR.UTF-8/tr_TR.UTF-8/' /etc/locale.gen 2>/dev/null || true
sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen 2>/dev/null || true
locale-gen 2>/dev/null || true

# ── Root şifresi (installer ortamı için) ─────────────────────────────────────
echo "root:oxware" | chpasswd

# ── Calamares binary kontrol ──────────────────────────────────────────────────
if ! command -v calamares &>/dev/null; then
    echo "[WARN] calamares bulunamadı — alternatif kaynak deneniyor..."
    apt-get install -y -qq calamares 2>/dev/null || true
fi
_CALA=$(command -v calamares 2>/dev/null || echo "")
echo "[INFO] calamares: ${_CALA:-BULUNAMADI}"
[ -z "$_CALA" ] && echo "[ERROR] Calamares kurulum BAŞARISIZ" && exit 1
CHROOT

_umount_all
trap - EXIT
log "Chroot paketler OK"

# ── OXware Calamares Config ───────────────────────────────────────────────────
step "OXware Calamares Konfigürasyonu"

CALA_SRC="$SCRIPT_DIR/calamares"

rm -rf "$SQUASHFS_ROOT/etc/calamares"
mkdir -p "$SQUASHFS_ROOT/etc/calamares/modules"

cp "$CALA_SRC/settings.conf" "$SQUASHFS_ROOT/etc/calamares/"

for conf in welcome locale keyboard partition users summary finished; do
    [ -f "$CALA_SRC/modules/${conf}.conf" ] && \
        cp "$CALA_SRC/modules/${conf}.conf" "$SQUASHFS_ROOT/etc/calamares/modules/"
done

# Custom Python job (Calamares → install.py --headless)
mkdir -p "$SQUASHFS_ROOT/usr/lib/calamares/modules/oxware_install"
cp "$CALA_SRC/modules/oxware_install/module.desc" \
   "$SQUASHFS_ROOT/usr/lib/calamares/modules/oxware_install/"
cp "$CALA_SRC/modules/oxware_install/main.py" \
   "$SQUASHFS_ROOT/usr/lib/calamares/modules/oxware_install/"

# OXware branding
mkdir -p "$SQUASHFS_ROOT/usr/share/calamares/branding/oxware"
cp "$CALA_SRC/branding/oxware/branding.desc" \
   "$SQUASHFS_ROOT/usr/share/calamares/branding/oxware/"
cp "$CALA_SRC/branding/oxware/show.qml" \
   "$SQUASHFS_ROOT/usr/share/calamares/branding/oxware/"

if [ -f "$REPO_ROOT/oxware/frontend/static/img/oxware2.png" ]; then
    cp "$REPO_ROOT/oxware/frontend/static/img/oxware2.png" \
       "$SQUASHFS_ROOT/usr/share/calamares/branding/oxware/oxware_logo.png"
    cp "$REPO_ROOT/oxware/frontend/static/img/oxware2.png" \
       "$SQUASHFS_ROOT/usr/share/calamares/branding/oxware/oxware_welcome.png"
fi
[ -f "$REPO_ROOT/oxware/frontend/static/img/sadeceikon.png" ] && \
    cp "$REPO_ROOT/oxware/frontend/static/img/sadeceikon.png" \
       "$SQUASHFS_ROOT/usr/share/calamares/branding/oxware/oxware_icon.png"

# Xorg minimal config (modesetting, sanal ortam dahil)
mkdir -p "$SQUASHFS_ROOT/etc/X11/xorg.conf.d"
cat > "$SQUASHFS_ROOT/etc/X11/xorg.conf.d/10-oxware.conf" << 'XORGCONF'
Section "Device"
    Identifier "OXware-Display"
    Driver     "modesetting"
EndSection

Section "Screen"
    Identifier "Default Screen"
    DefaultDepth 24
    SubSection "Display"
        Depth    24
        Modes    "1024x768" "800x600" "1280x1024"
    EndSubSection
EndSection
XORGCONF

log "Calamares config OK"

# ── OXware Installer Backend ──────────────────────────────────────────────────
step "OXware Backend"

mkdir -p "$SQUASHFS_ROOT/opt/oxware-installer"
cp "$SCRIPT_DIR/installer/install.py" "$SQUASHFS_ROOT/opt/oxware-installer/"
chmod +x "$SQUASHFS_ROOT/opt/oxware-installer/install.py"

# Ağ yapılandırma GUI (netcfg-gui.py — Calamares öncesi çalışır)
[ -f "$SCRIPT_DIR/installer/netcfg-gui.py" ] && {
    cp "$SCRIPT_DIR/installer/netcfg-gui.py" "$SQUASHFS_ROOT/opt/oxware-installer/"
    chmod +x "$SQUASHFS_ROOT/opt/oxware-installer/netcfg-gui.py"
    log "netcfg-gui.py kopyalandı"
}

# debootstrap
[ -f "/usr/sbin/debootstrap" ] && {
    cp /usr/sbin/debootstrap "$SQUASHFS_ROOT/usr/sbin/debootstrap"
    chmod +x "$SQUASHFS_ROOT/usr/sbin/debootstrap"
}
[ -d "/usr/share/debootstrap" ] && {
    mkdir -p "$SQUASHFS_ROOT/usr/share/debootstrap"
    cp -r /usr/share/debootstrap/. "$SQUASHFS_ROOT/usr/share/debootstrap/"
}
for kdir in /usr/share/keyrings /etc/apt/trusted.gpg.d; do
    [ -d "$kdir" ] && {
        mkdir -p "$SQUASHFS_ROOT$kdir"
        cp "$kdir"/*.gpg "$SQUASHFS_ROOT$kdir/" 2>/dev/null || true
        cp "$kdir"/*.asc "$SQUASHFS_ROOT$kdir/" 2>/dev/null || true
    }
done

# OXware web backend (offline)
rsync -a --exclude='.git' --exclude='*.pyc' --exclude='__pycache__' \
    "$REPO_ROOT/oxware/" "$SQUASHFS_ROOT/opt/oxware/"

log "Backend OK"

# ── Boot: getty autologin root → startx → Calamares ─────────────────────────
# PROXMOX VE ile AYNI mantık: display manager YOK, desktop YOK
# Sadece: tty1 autologin → X11 → Calamares fullscreen
step "Boot: getty autologin root → Calamares"

# 1. getty@tty1 autologin root
mkdir -p "$SQUASHFS_ROOT/etc/systemd/system/getty@tty1.service.d"
cat > "$SQUASHFS_ROOT/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
Type=simple
GETTY

# 2. root .bash_profile: tty1'de otomatik startx
cat > "$SQUASHFS_ROOT/root/.bash_profile" << 'BASHPROF'
# OXware Installer: tty1'de otomatik X başlat
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$DISPLAY" ]; then
    exec startx /opt/oxware-installer/oxware-start.sh -- :0 -nolisten tcp vt1
fi
BASHPROF

# 2b. /etc/profile.d fallback — hem root hem "user" için çalışır
# live-config "user" autologin'i kazanırsa bu devreye girer
cat > "$SQUASHFS_ROOT/etc/profile.d/oxware-installer.sh" << 'PROFILED'
# OXware Installer: tty1'de otomatik X başlat (root veya user)
if [ "$(tty)" = "/dev/tty1" ] && [ -z "$DISPLAY" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        exec startx /opt/oxware-installer/oxware-start.sh -- :0 -nolisten tcp vt1
    else
        exec sudo -n startx /opt/oxware-installer/oxware-start.sh -- :0 -nolisten tcp vt1
    fi
fi
PROFILED
chmod +x "$SQUASHFS_ROOT/etc/profile.d/oxware-installer.sh"

# sudoers: "user" da startx çalıştırabilsin (live-config fallback için)
echo "user ALL=(root) NOPASSWD: /usr/bin/startx" \
    > "$SQUASHFS_ROOT/etc/sudoers.d/oxware-user"
chmod 440 "$SQUASHFS_ROOT/etc/sudoers.d/oxware-user"

# 3. oxware-start.sh: X oturumu başlat
cat > "$SQUASHFS_ROOT/opt/oxware-installer/oxware-start.sh" << 'STARTSH'
#!/bin/bash
# OXware X Installer Session — Network config then Calamares
LOG=/tmp/oxware-start.log
exec >> "$LOG" 2>&1
echo "=== OXware start: $(date) uid=$(id -u) ==="

export DISPLAY=:0
export HOME=/root
export XDG_RUNTIME_DIR=/tmp/xdg-oxware
export LANG=tr_TR.UTF-8
export FONTCONFIG_PATH=/etc/fonts
# Qt5 xcb platform — X11 gerekli
export QT_QPA_PLATFORM=xcb
export QT_QPA_PLATFORMTHEME=
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Lacivert arka plan
xsetroot -solid '#0d2340' 2>/dev/null || true
xsetroot -cursor_name left_ptr 2>/dev/null || true
xrandr --auto 2>/dev/null || true
echo "X11 hazır"

# D-Bus system + session bus (Calamares partition backend için zorunlu)
if command -v dbus-daemon &>/dev/null; then
    dbus-daemon --system 2>/dev/null || true
    sleep 0.5
fi
if command -v dbus-launch &>/dev/null; then
    eval "$(dbus-launch --auto-syntax)" || true
    echo "D-Bus session: $DBUS_SESSION_BUS_ADDRESS"
fi
# udisks2 — Calamares disk listesi için
if command -v udisksd &>/dev/null; then
    udisksd --no-debug 2>/dev/null &
    sleep 0.5
fi

# Font cache
fc-cache -f 2>/dev/null || true

# ── 1. Ağ yapılandırması (Proxmox tarzı — Calamares öncesi) ──────────────────
if [ -f /opt/oxware-installer/netcfg-gui.py ]; then
    echo "netcfg-gui başlıyor..."
    timeout 180 python3 /opt/oxware-installer/netcfg-gui.py 2>/tmp/netcfg-gui.log || \
        echo "netcfg-gui çıktı: $?"
    xsetroot -solid '#0d2340' 2>/dev/null || true
    echo "netcfg-gui tamamlandı"
fi

# ── 2. Calamares fullscreen kurulum ──────────────────────────────────────────
echo "Calamares başlıyor..."
/usr/bin/calamares -D 6 > /tmp/calamares.log 2>&1
_EXIT=$?
echo "Calamares çıktı: $_EXIT"

# Calamares kapanırsa xterm ile hata göster
xterm -bg '#0d2340' -fg '#c5d8f0' -fs 12 \
    -title 'OXware — Hata Ayıklama' \
    -e "bash -c \"echo '=== Calamares Log (son 60 satır) ==='; \
        tail -60 /tmp/calamares.log 2>/dev/null || echo 'log yok'; \
        echo; echo '=== Başlatma Log ==='; cat $LOG 2>/dev/null; \
        echo; echo 'Çıkmak için Enter'; read\"" \
    2>/dev/null || true
STARTSH
chmod +x "$SQUASHFS_ROOT/opt/oxware-installer/oxware-start.sh"

# 4. sudoers (Calamares bazı çağrılar için)
echo "root ALL=(ALL) NOPASSWD: ALL" \
    > "$SQUASHFS_ROOT/etc/sudoers.d/oxware-root"
chmod 440 "$SQUASHFS_ROOT/etc/sudoers.d/oxware-root"

# 5. systemd default target: multi-user (graphical değil — DM yok)
ln -sf /lib/systemd/system/multi-user.target \
    "$SQUASHFS_ROOT/etc/systemd/system/default.target" 2>/dev/null || true

log "getty autologin root → Calamares OK"

# ── Squashfs Yeniden Paketle ──────────────────────────────────────────────────
step "Squashfs Paketleniyor (~10-15 dk)"
rm -f "$SQUASHFS_FILE"
mksquashfs "$SQUASHFS_ROOT" "$SQUASHFS_FILE" \
    -comp xz -noappend -b 1M -no-progress
printf '%s' "$(du -sx --block-size=1 "$SQUASHFS_ROOT" | cut -f1)" \
    > "$(dirname "$SQUASHFS_FILE")/filesystem.size"
log "Squashfs: $(du -sh "$SQUASHFS_FILE" | cut -f1)"

# ── GRUB Boot Menüsü ──────────────────────────────────────────────────────────
step "GRUB Boot Menüsü"

# Kernel ve initrd yollarını bul
VMLINUZ_PATH=""
INITRD_PATH=""
for vp in "${LIVE_DIR}/vmlinuz" "${LIVE_DIR}/vmlinuz.efi" "/casper/vmlinuz"; do
    [ -f "$WORK_DIR/iso$vp" ] && VMLINUZ_PATH="$vp" && break
done
for ip in "${LIVE_DIR}/initrd" "${LIVE_DIR}/initrd.img" "${LIVE_DIR}/initrd.gz" "/casper/initrd"; do
    [ -f "$WORK_DIR/iso$ip" ] && INITRD_PATH="$ip" && break
done
[ -z "$VMLINUZ_PATH" ] && VMLINUZ_PATH="${LIVE_DIR}/vmlinuz"
[ -z "$INITRD_PATH"  ] && INITRD_PATH="${LIVE_DIR}/initrd"

log "vmlinuz: $VMLINUZ_PATH"
log "initrd:  $INITRD_PATH"

mkdir -p "$WORK_DIR/iso/boot/grub"
cat > "$WORK_DIR/iso/boot/grub/grub.cfg" << GRUBEOF
set default=0
set timeout=5

insmod all_video
insmod gfxterm
terminal_output gfxterm

# OXware boot ekranı
background_color 10,23,40

menuentry "OXware Hypervisor ${OXWARE_VERSION} — Install" --class oxware {
    linux   ${VMLINUZ_PATH} boot=live components quiet splash vga=791 loglevel=0 live-config.noautologin ---
    initrd  ${INITRD_PATH}
}

menuentry "OXware Hypervisor ${OXWARE_VERSION} — Install (nomodeset)" --class oxware {
    linux   ${VMLINUZ_PATH} boot=live components quiet nomodeset vga=normal loglevel=0 live-config.noautologin ---
    initrd  ${INITRD_PATH}
}

menuentry "OXware Installer — Debug (verbose)" --class oxware {
    linux   ${VMLINUZ_PATH} boot=live components live-config.noautologin ---
    initrd  ${INITRD_PATH}
}
GRUBEOF

log "GRUB OK"

# ── md5sum ────────────────────────────────────────────────────────────────────
cd "$WORK_DIR/iso"
find . -type f ! -name 'md5sum.txt' | sort | xargs md5sum > md5sum.txt 2>/dev/null || true
cd - > /dev/null

# ── ISO Oluştur ───────────────────────────────────────────────────────────────
step "ISO Oluşturma"

_FREE_KB2=$(df -k "$PWD" | awk 'NR==2{print $4}')
[ "$_FREE_KB2" -lt 3145728 ] && err "ISO için yer yok"

_VOLID="OXWARE_$(echo "$OXWARE_VERSION" | tr '.' '_')"
_TMP_ISO="$WORK_DIR/output.iso"

_make_iso() {
    local OUT="$1"

    # grub-mkrescue — en güvenilir
    if command -v grub-mkrescue &>/dev/null; then
        log "grub-mkrescue ile ISO oluşturuluyor..."
        grub-mkrescue -o "$OUT" "$WORK_DIR/iso" \
            -- -volid "$_VOLID" 2>&1 | tail -5
        [ -s "$OUT" ] && return 0
        rm -f "$OUT"
    fi

    # xorriso fallback
    if command -v xorriso &>/dev/null; then
        log "xorriso ile ISO oluşturuluyor..."
        local MBR=""
        for f in \
            /usr/lib/grub/i386-pc/boot_hybrid.img \
            /usr/share/grub/boot_hybrid.img; do
            [ -f "$f" ] && MBR="$f" && break
        done
        local XARGS=(-as mkisofs -r -V "$_VOLID" -o "$OUT" -J -l -iso-level 3)
        [ -n "$MBR" ] && XARGS+=(--grub2-mbr "$MBR")
        [ -f "$WORK_DIR/iso/isolinux/isolinux.bin" ] && \
            XARGS+=(-b isolinux/isolinux.bin -c isolinux/boot.cat \
                    -no-emul-boot -boot-load-size 4 -boot-info-table)
        [ -f "$WORK_DIR/iso/boot/grub/efi.img" ] && \
            XARGS+=(-eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot)
        XARGS+=("$WORK_DIR/iso")
        xorriso "${XARGS[@]}" 2>&1 | tail -5
        [ -s "$OUT" ] && return 0
        rm -f "$OUT"
    fi

    # genisoimage son çare
    if command -v genisoimage &>/dev/null; then
        log "genisoimage ile ISO oluşturuluyor..."
        genisoimage -r -V "$_VOLID" -cache-inodes -J -l \
            -o "$OUT" "$WORK_DIR/iso" 2>&1 | tail -3
        [ -s "$OUT" ] && return 0
        rm -f "$OUT"
    fi

    return 1
}

_make_iso "$_TMP_ISO" || err "ISO oluşturma başarısız!"

# Eski ISO'ları temizle
find "$REPO_ROOT" -maxdepth 1 \
    -name "OXware-Hypervisor-*.iso" \
    ! -name "$(basename "$OUTPUT_ISO")" \
    -delete 2>/dev/null || true

mv "$_TMP_ISO" "$OUTPUT_ISO"

# isohybrid: USB'den boot için
if command -v isohybrid &>/dev/null && [ -s "$OUTPUT_ISO" ]; then
    isohybrid --uefi "$OUTPUT_ISO" 2>/dev/null || \
    isohybrid "$OUTPUT_ISO" 2>/dev/null || true
    log "isohybrid uygulandı (USB bootable)"
fi

[ ! -s "$OUTPUT_ISO" ] && err "ISO boş (0 byte)!"

sha256sum "$OUTPUT_ISO" > "${OUTPUT_ISO}.sha256"
rm -rf "$WORK_DIR"

ISO_SIZE=$(du -sh "$OUTPUT_ISO" | cut -f1)
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}           ${WHITE}OXware Hypervisor ISO Hazır!${NC}                       ${CYAN}║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  Dosya   : ${WHITE}$(basename "$OUTPUT_ISO")${NC}"
echo -e "${CYAN}║${NC}  Boyut   : ${WHITE}${ISO_SIZE}${NC}"
echo -e "${CYAN}║${NC}  SHA256  : ${WHITE}$(head -c 32 "${OUTPUT_ISO}.sha256")...${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  Boot akışı:                                               ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  GRUB → live-boot → getty autologin root → startx         ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  → Calamares fullscreen (OXware branding, Türkçe)          ${CYAN}║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  USB: sudo dd if=$(basename "$OUTPUT_ISO") of=/dev/sdX bs=4M${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# OXware ISO kütüphanesine kopyala
OXWARE_ISO_DIR="/var/lib/oxware/isos"
[ -d "$OXWARE_ISO_DIR" ] && {
    cp -f "$OUTPUT_ISO" "$OXWARE_ISO_DIR/"
    cp -f "${OUTPUT_ISO}.sha256" "$OXWARE_ISO_DIR/" 2>/dev/null || true
    log "ISO kütüphanesine kopyalandı: $OXWARE_ISO_DIR"
}
