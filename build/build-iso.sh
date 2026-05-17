#!/usr/bin/env bash
# ============================================================
#  OXware Hypervisor — ISO Builder v4.0
#  Base: Lubuntu 22.04 LTS (Calamares + LXQt + X11 built-in)
#  Ubuntu Server'ın subiquity/overlay karmaşası yok.
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
# Lubuntu 22.04 LTS — Calamares + LXQt çalışan tek squashfs, overlay yok
LUBUNTU_ISO_URL="https://cdimage.ubuntu.com/lubuntu/releases/22.04/release/lubuntu-22.04.5-desktop-amd64.iso"
ISO_CACHE="/tmp/lubuntu-22.04.5-desktop-amd64.iso"
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
    genisoimage grub-pc-bin grub-efi-amd64-bin mtools \
    debootstrap rsync python3 \
    python3-yaml syslinux-utils 2>/dev/null || true
log "Bağımlılıklar hazır"

# ── Disk alanı (20GB minimum — Lubuntu base ~5GB) ─────────────────────────────
_FREE_KB=$(df -k "$PWD" | awk 'NR==2{print $4}')
[ "$_FREE_KB" -lt 20971520 ] && \
    err "Yetersiz disk: $(df -h "$PWD" | awk 'NR==2{print $4}') boş, en az 20GB gerek"
log "Disk: $(df -h "$PWD" | awk 'NR==2{print $4}') boş"

# ── Lubuntu ISO indir ─────────────────────────────────────────────────────────
step "Lubuntu 22.04 LTS ISO"
if [ -f "$ISO_CACHE" ]; then
    log "Cache'de mevcut: $ISO_CACHE ($(du -sh "$ISO_CACHE" | cut -f1))"
else
    log "İndiriliyor (~2.7 GB): $LUBUNTU_ISO_URL"
    wget -q --show-progress -c -O "$ISO_CACHE" "$LUBUNTU_ISO_URL" || \
        err "İndirme başarısız.\nManuel: wget -O $ISO_CACHE $LUBUNTU_ISO_URL"
fi

# ── ISO Ayıkla ────────────────────────────────────────────────────────────────
step "ISO Ayıklama"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/iso"
xorriso -osirrox on -indev "$ISO_CACHE" -extract / "$WORK_DIR/iso" 2>/dev/null \
    || err "ISO ayıklanamadı"
chmod -R u+w "$WORK_DIR/iso"
log "ISO içeriği hazır"

# ── Squashfs bul (Lubuntu: tek filesystem.squashfs) ───────────────────────────
step "Squashfs"
SQUASHFS_FILE="$WORK_DIR/iso/casper/filesystem.squashfs"
[ -f "$SQUASHFS_FILE" ] || err "filesystem.squashfs bulunamadı!"
log "Squashfs: $SQUASHFS_FILE ($(du -sh "$SQUASHFS_FILE" | cut -f1))"

# ── Squashfs Aç ───────────────────────────────────────────────────────────────
step "Squashfs Açılıyor (~5-10 dk)"
unsquashfs -d "$SQUASHFS_ROOT" "$SQUASHFS_FILE"
log "Açıldı: $(du -sh "$SQUASHFS_ROOT" | cut -f1)"

# ── Calamares Config: Lubuntu'nunkini sil, OXware'inkini koy ─────────────────
step "OXware Calamares Konfigürasyonu"

CALA_SRC="$SCRIPT_DIR/calamares"

# Lubuntu'nun Calamares config'ini tamamen temizle
rm -rf "$SQUASHFS_ROOT/etc/calamares"
mkdir -p "$SQUASHFS_ROOT/etc/calamares/modules"

# Ana settings
cp "$CALA_SRC/settings.conf" "$SQUASHFS_ROOT/etc/calamares/"

# Modül configleri
for conf in welcome locale keyboard partition users summary finished; do
    [ -f "$CALA_SRC/modules/${conf}.conf" ] && \
        cp "$CALA_SRC/modules/${conf}.conf" "$SQUASHFS_ROOT/etc/calamares/modules/"
done

# OXware Python job modülü
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

# Logolar
if [ -f "$REPO_ROOT/oxware/frontend/static/img/oxware2.png" ]; then
    cp "$REPO_ROOT/oxware/frontend/static/img/oxware2.png" \
       "$SQUASHFS_ROOT/usr/share/calamares/branding/oxware/oxware_logo.png"
    cp "$REPO_ROOT/oxware/frontend/static/img/oxware2.png" \
       "$SQUASHFS_ROOT/usr/share/calamares/branding/oxware/oxware_welcome.png"
fi
[ -f "$REPO_ROOT/oxware/frontend/static/img/sadeceikon.png" ] && \
    cp "$REPO_ROOT/oxware/frontend/static/img/sadeceikon.png" \
       "$SQUASHFS_ROOT/usr/share/calamares/branding/oxware/oxware_icon.png"

log "Calamares config OK"

# ── OXware Installer Backend ──────────────────────────────────────────────────
step "OXware Installer Backend"

mkdir -p "$SQUASHFS_ROOT/opt/oxware-installer"
cp "$SCRIPT_DIR/installer/install.py" "$SQUASHFS_ROOT/opt/oxware-installer/"
chmod +x "$SQUASHFS_ROOT/opt/oxware-installer/install.py"

# OXware backend (offline fallback)
rsync -a --exclude='.git' --exclude='*.pyc' --exclude='__pycache__' \
    "$REPO_ROOT/oxware/" "$SQUASHFS_ROOT/opt/oxware/"

# debootstrap binary + scripts
if [ -f "/usr/sbin/debootstrap" ]; then
    cp /usr/sbin/debootstrap "$SQUASHFS_ROOT/usr/sbin/debootstrap"
    chmod +x "$SQUASHFS_ROOT/usr/sbin/debootstrap"
fi
[ -d "/usr/share/debootstrap" ] && {
    mkdir -p "$SQUASHFS_ROOT/usr/share/debootstrap"
    cp -r /usr/share/debootstrap/. "$SQUASHFS_ROOT/usr/share/debootstrap/"
}
# GPG keyrings (debootstrap'in ihtiyacı var)
for kdir in /usr/share/keyrings /etc/apt/trusted.gpg.d; do
    [ -d "$kdir" ] && {
        mkdir -p "$SQUASHFS_ROOT$kdir"
        cp "$kdir"/*.gpg "$SQUASHFS_ROOT$kdir/" 2>/dev/null || true
        cp "$kdir"/*.asc "$SQUASHFS_ROOT$kdir/" 2>/dev/null || true
    }
done

log "Backend OK"

# ── LightDM → Calamares Otomatik Başlatma ────────────────────────────────────
step "LightDM Autologin → Calamares"

# LightDM: ubuntu kullanıcısını otomatik oturum aç, oxware-installer session çalıştır
mkdir -p "$SQUASHFS_ROOT/etc/lightdm"
cat > "$SQUASHFS_ROOT/etc/lightdm/lightdm.conf" << 'LIGHTDM'
[Seat:*]
autologin-user=ubuntu
autologin-user-timeout=0
autologin-session=oxware-installer
user-session=oxware-installer
LIGHTDM

# X session desktop entry
mkdir -p "$SQUASHFS_ROOT/usr/share/xsessions"
cat > "$SQUASHFS_ROOT/usr/share/xsessions/oxware-installer.desktop" << 'XSESSION'
[Desktop Entry]
Name=OXware Hypervisor Installer
Exec=/opt/oxware-installer/oxware-session.sh
Type=Application
NoDisplay=true
XSESSION

# Session script: koyu arka plan + Calamares (Proxmox tarzı tam ekran)
cat > "$SQUASHFS_ROOT/opt/oxware-installer/oxware-session.sh" << 'SESS'
#!/bin/bash
export DISPLAY=:0
export XDG_RUNTIME_DIR="/tmp/xdg-$$"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Koyu navy arka plan, imleç
xsetroot -solid '#0a1628' 2>/dev/null || true
xsetroot -cursor_name left_ptr 2>/dev/null || true

# Calamares: disk partitioning için root yetkisi gerekli
exec sudo /usr/bin/calamares
SESS
chmod +x "$SQUASHFS_ROOT/opt/oxware-installer/oxware-session.sh"

# sudoers: ubuntu kullanıcısı calamares'i root olarak çalıştırabilsin
echo "ubuntu ALL=(ALL) NOPASSWD: /usr/bin/calamares" \
    > "$SQUASHFS_ROOT/etc/sudoers.d/oxware-calamares"
chmod 440 "$SQUASHFS_ROOT/etc/sudoers.d/oxware-calamares"

log "Autologin → oxware-installer session OK"

# ── Chroot: Ek Paketler ───────────────────────────────────────────────────────
step "Chroot: Ek Paketler"

mkdir -p "$SQUASHFS_ROOT/proc" "$SQUASHFS_ROOT/sys" \
         "$SQUASHFS_ROOT/dev"  "$SQUASHFS_ROOT/dev/pts"
cp /etc/resolv.conf "$SQUASHFS_ROOT/etc/resolv.conf" 2>/dev/null || true

_umount_all() {
    umount "$SQUASHFS_ROOT/dev/pts" 2>/dev/null || true
    umount "$SQUASHFS_ROOT/dev"     2>/dev/null || true
    umount "$SQUASHFS_ROOT/sys"     2>/dev/null || true
    umount "$SQUASHFS_ROOT/proc"    2>/dev/null || true
}
trap _umount_all EXIT

mount --bind /proc    "$SQUASHFS_ROOT/proc"
mount --bind /sys     "$SQUASHFS_ROOT/sys"
mount --bind /dev     "$SQUASHFS_ROOT/dev"
mount --bind /dev/pts "$SQUASHFS_ROOT/dev/pts"

chroot "$SQUASHFS_ROOT" /bin/bash << 'CHROOT'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>/dev/null || true

# Calamares partition modülü için kpmcore + python3-parted
apt-get install -y -qq --no-install-recommends \
    parted \
    python3-parted \
    python3-yaml \
    dosfstools \
    e2fsprogs \
    util-linux \
    iproute2 \
    2>/dev/null || true

# libkpmcore (Calamares partition module bağımlılığı)
apt-get install -y -qq --no-install-recommends \
    libkpmcore11 \
    2>/dev/null || true

# Emin olmak için calamares kurulu olsun
apt-get install -y -qq --no-install-recommends \
    calamares calamares-data \
    2>/dev/null || true
CHROOT

_umount_all
trap - EXIT
log "Chroot OK"

# ── Squashfs Yeniden Paketle ──────────────────────────────────────────────────
step "Squashfs Paketleniyor (~10-15 dk)"
rm -f "$SQUASHFS_FILE"
mksquashfs "$SQUASHFS_ROOT" "$SQUASHFS_FILE" \
    -comp xz -noappend -b 1M -no-progress
printf '%s' "$(du -sx --block-size=1 "$SQUASHFS_ROOT" | cut -f1)" \
    > "$WORK_DIR/iso/casper/filesystem.size"
log "Squashfs: $(du -sh "$SQUASHFS_FILE" | cut -f1)"

# ── GRUB ─────────────────────────────────────────────────────────────────────
step "GRUB Boot Menüsü"

VMLINUZ_PATH=""
INITRD_PATH=""
for vp in /casper/vmlinuz /casper/vmlinuz.efi; do
    [ -f "$WORK_DIR/iso$vp" ] && VMLINUZ_PATH="$vp" && break
done
for ip in /casper/initrd /casper/initrd.gz; do
    [ -f "$WORK_DIR/iso$ip" ] && INITRD_PATH="$ip" && break
done
[ -z "$VMLINUZ_PATH" ] && VMLINUZ_PATH="/casper/vmlinuz"
[ -z "$INITRD_PATH"  ] && INITRD_PATH="/casper/initrd"

mkdir -p "$WORK_DIR/iso/boot/grub"
cat > "$WORK_DIR/iso/boot/grub/grub.cfg" << GRUBEOF
set default=0
set timeout=5

menuentry "OXware Hypervisor Installer ${OXWARE_VERSION}" {
    linux   ${VMLINUZ_PATH} boot=casper quiet splash loglevel=0 ---
    initrd  ${INITRD_PATH}
}

menuentry "OXware Installer (nomodeset — GPU sorunu varsa)" {
    linux   ${VMLINUZ_PATH} boot=casper quiet nomodeset loglevel=0 ---
    initrd  ${INITRD_PATH}
}

menuentry "OXware Installer (Debug)" {
    linux   ${VMLINUZ_PATH} boot=casper ---
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
[ "$_FREE_KB2" -lt 3145728 ] && err "ISO için yeterli alan yok"

_VOLID="OXWARE_$(echo "$OXWARE_VERSION" | tr '.' '_')"
_TMP_ISO="$WORK_DIR/output.iso"

_make_iso() {
    local OUT="$1"

    if command -v grub-mkrescue &>/dev/null; then
        log "grub-mkrescue..."
        grub-mkrescue -o "$OUT" "$WORK_DIR/iso" -- -volid "$_VOLID" 2>&1 | tail -3
        [ -s "$OUT" ] && return 0
        rm -f "$OUT"
    fi

    if command -v xorriso &>/dev/null; then
        log "xorriso..."
        local MBR_FILE=""
        for f in /usr/lib/grub/i386-pc/boot_hybrid.img /usr/share/grub/boot_hybrid.img; do
            [ -f "$f" ] && MBR_FILE="$f" && break
        done
        local XARGS=(-as mkisofs -r -V "$_VOLID" -o "$OUT" -J -l -iso-level 3)
        [ -n "$MBR_FILE" ] && XARGS+=(--grub2-mbr "$MBR_FILE")
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

    if command -v genisoimage &>/dev/null; then
        log "genisoimage..."
        genisoimage -r -V "$_VOLID" -cache-inodes -J -l -joliet-long \
            -o "$OUT" "$WORK_DIR/iso" 2>&1 | tail -3
        [ -s "$OUT" ] && return 0
        rm -f "$OUT"
    fi

    return 1
}

_make_iso "$_TMP_ISO" || err "ISO oluşturma başarısız!"

# Eski ISO'ları temizle
find "$REPO_ROOT" -maxdepth 1 -name "OXware-Hypervisor-*.iso" \
    ! -name "$(basename "$OUTPUT_ISO")" -delete 2>/dev/null || true
find "$REPO_ROOT" -maxdepth 1 -name "OXware-Hypervisor-*.sha256" \
    ! -name "$(basename "$OUTPUT_ISO").sha256" -delete 2>/dev/null || true

mv "$_TMP_ISO" "$OUTPUT_ISO"

# isohybrid (USB bootable)
if command -v isohybrid &>/dev/null && [ -s "$OUTPUT_ISO" ]; then
    isohybrid --uefi "$OUTPUT_ISO" 2>/dev/null || isohybrid "$OUTPUT_ISO" 2>/dev/null || true
    log "isohybrid uygulandı"
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
echo -e "${CYAN}║${NC}  Boot: LightDM → OXware session → Calamares (Qt5 GUI)      ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Web UI: https://<ip>:8006 (kurulum sonrası)               ${CYAN}║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  USB: sudo dd if=$(basename "$OUTPUT_ISO") of=/dev/sdX bs=4M ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

# OXware ISO kütüphanesine kopyala
OXWARE_ISO_DIR="/var/lib/oxware/isos"
if [ -d "$OXWARE_ISO_DIR" ]; then
    cp -f "$OUTPUT_ISO" "$OXWARE_ISO_DIR/"
    cp -f "${OUTPUT_ISO}.sha256" "$OXWARE_ISO_DIR/" 2>/dev/null || true
    log "ISO kütüphanesine kopyalandı: $OXWARE_ISO_DIR"
fi
