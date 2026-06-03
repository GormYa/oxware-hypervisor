#!/usr/bin/env bash
# ============================================================================
# OXware Hypervisor — Kernel Security Hardening Installer
# Installs: AppArmor profile, seccomp filter, systemd drop-in,
#           eBPF/XDP loader, kernel modules (oxware_audit + oxware_guard)
# Usage:
#   sudo bash kernel/install-hardening.sh [--dry-run] [--no-modules] [--complain]
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
NO_MODULES=0
APPARMOR_MODE="enforce"  # or "complain"
LOG=/var/log/oxware/hardening-install.log

# ── Parse args ────────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=1 ;;
    --no-modules) NO_MODULES=1 ;;
    --complain)   APPARMOR_MODE="complain" ;;
    --help|-h)
      echo "Usage: sudo bash install-hardening.sh [--dry-run] [--no-modules] [--complain]"
      echo "  --dry-run    Show what would be done without making changes"
      echo "  --no-modules Skip kernel module compilation/install"
      echo "  --complain   Install AppArmor in complain mode (log only, no block)"
      exit 0 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$LOG"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG"; }
error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG"; }
run()   {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY-RUN] $*"
  else
    eval "$@" 2>&1 | tee -a "$LOG" || true
  fi
}

# ── Root check ────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Root required. Run: sudo bash $0"
  exit 1
fi

mkdir -p /var/log/oxware
info "OXware Kernel Hardening Installer — $(date)"
info "Mode: DRY_RUN=$DRY_RUN NO_MODULES=$NO_MODULES APPARMOR=$APPARMOR_MODE"

# ── 1. AppArmor ───────────────────────────────────────────────────────────
info "--- [1/5] AppArmor Profile ---"
if ! command -v apparmor_parser &>/dev/null; then
  warn "apparmor_parser not found. Installing..."
  run "apt-get install -y apparmor apparmor-utils apparmor-profiles"
fi

APPARMOR_PROFILE="/etc/apparmor.d/opt.oxware.backend.app"
run "cp '$SCRIPT_DIR/apparmor/oxware' '$APPARMOR_PROFILE'"

if [[ $APPARMOR_MODE == "complain" ]]; then
  run "aa-complain '$APPARMOR_PROFILE'"
  info "AppArmor installed in COMPLAIN mode (logging only, no blocking)"
  info "Monitor: sudo journalctl -f | grep apparmor"
else
  run "apparmor_parser -r '$APPARMOR_PROFILE'"
  run "aa-enforce '$APPARMOR_PROFILE'"
  info "AppArmor profile installed and enforced: $APPARMOR_PROFILE"
fi

# ── 2. seccomp filter ─────────────────────────────────────────────────────
info "--- [2/5] seccomp Filter ---"
SECCOMP_DEST="/etc/oxware/seccomp.json"
run "cp '$SCRIPT_DIR/seccomp/oxware-seccomp.json' '$SECCOMP_DEST'"
run "chmod 640 '$SECCOMP_DEST'"
info "seccomp profile installed: $SECCOMP_DEST"
info "Used via systemd SystemCallFilter= in drop-in (no app changes needed)"

# ── 3. systemd drop-in (cgroups + capabilities + seccomp) ─────────────────
info "--- [3/5] systemd Hardening Drop-in ---"
DROPIN_DIR="/etc/systemd/system/oxware.service.d"
run "mkdir -p '$DROPIN_DIR'"
run "cp '$SCRIPT_DIR/systemd/oxware-hardening.conf' '$DROPIN_DIR/hardening.conf'"
run "systemctl daemon-reload"
info "systemd drop-in installed: $DROPIN_DIR/hardening.conf"
info "Effective after: sudo systemctl restart oxware"

# ── 4. eBPF/XDP network filter ────────────────────────────────────────────
info "--- [4/5] eBPF/XDP Network Filter ---"
EBPF_DIR="/opt/oxware/kernel/ebpf"
run "mkdir -p '$EBPF_DIR'"
run "cp '$SCRIPT_DIR/ebpf/xdp_filter.c' '$EBPF_DIR/'"
run "cp '$SCRIPT_DIR/ebpf/xdp_loader.py' '$EBPF_DIR/'"
run "chmod +x '$EBPF_DIR/xdp_loader.py'"

# Compile XDP object if clang is available
if command -v clang &>/dev/null; then
  info "Compiling XDP filter (clang found)..."
  run "clang -O2 -g -target bpf -D__TARGET_ARCH_x86 \
    -I/usr/include/$(uname -m)-linux-gnu \
    -c '$EBPF_DIR/xdp_filter.c' -o '$EBPF_DIR/xdp_filter.o' 2>&1 || true"
  if [[ -f "$EBPF_DIR/xdp_filter.o" ]]; then
    info "XDP filter compiled: $EBPF_DIR/xdp_filter.o"
    info "To attach to a VM tap: sudo python3 $EBPF_DIR/xdp_loader.py attach-all"
  fi
else
  warn "clang not found — XDP filter not compiled. Install: apt-get install -y clang linux-headers-\$(uname -r)"
fi

# Create systemd service for auto-attach on VM start
cat > /etc/systemd/system/oxware-xdp.service << 'SVCEOF'
[Unit]
Description=OXware XDP Network Filter — attach to VM tap interfaces
After=oxware.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/python3 /opt/oxware/kernel/ebpf/xdp_loader.py attach-all
ExecStop=/usr/bin/python3 /opt/oxware/kernel/ebpf/xdp_loader.py detach-all
Restart=no

[Install]
WantedBy=multi-user.target
SVCEOF
run "systemctl daemon-reload"
info "oxware-xdp.service installed (enable with: systemctl enable --now oxware-xdp)"

# ── 5. Kernel Modules ─────────────────────────────────────────────────────
info "--- [5/5] Kernel Modules ---"
if [[ $NO_MODULES -eq 1 ]]; then
  warn "Skipping kernel modules (--no-modules passed)"
else
  # Check kernel headers
  KDIR="/lib/modules/$(uname -r)/build"
  if [[ ! -d "$KDIR" ]]; then
    warn "Kernel headers not found at $KDIR. Installing..."
    run "apt-get install -y linux-headers-$(uname -r) build-essential"
  fi

  # oxware_audit
  AUDIT_DIR="$SCRIPT_DIR/modules/oxware_audit"
  if [[ -d "$AUDIT_DIR" ]]; then
    info "Building oxware_audit.ko..."
    run "make -C '$AUDIT_DIR' KDIR='$KDIR' 2>&1 || true"
    if [[ -f "$AUDIT_DIR/oxware_audit.ko" ]]; then
      run "install -m 644 '$AUDIT_DIR/oxware_audit.ko' '/lib/modules/$(uname -r)/extra/'"
      run "depmod -a"
      run "modprobe oxware_audit || true"
      run "echo 'oxware_audit' >> /etc/modules-load.d/oxware.conf"
      info "oxware_audit.ko installed and loaded"
    else
      warn "oxware_audit.ko build failed (check kernel config — need CONFIG_KPROBES=y)"
    fi
  fi

  # oxware_guard
  GUARD_DIR="$SCRIPT_DIR/modules/oxware_guard"
  if [[ -d "$GUARD_DIR" ]]; then
    info "Building oxware_guard.ko..."
    run "make -C '$GUARD_DIR' KDIR='$KDIR' 2>&1 || true"
    if [[ -f "$GUARD_DIR/oxware_guard.ko" ]]; then
      run "install -m 644 '$GUARD_DIR/oxware_guard.ko' '/lib/modules/$(uname -r)/extra/'"
      run "depmod -a"
      run "modprobe oxware_guard || true"
      run "echo 'oxware_guard' >> /etc/modules-load.d/oxware.conf"
      info "oxware_guard.ko installed and loaded"
    else
      warn "oxware_guard.ko build failed (check kernel config)"
    fi
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
info "════════════════════════════════════════════════"
info "OXware Kernel Hardening — Installation Complete"
info "════════════════════════════════════════════════"
echo ""
echo "  AppArmor:     /etc/apparmor.d/opt.oxware.backend.app  ($APPARMOR_MODE)"
echo "  seccomp:      /etc/oxware/seccomp.json"
echo "  systemd:      /etc/systemd/system/oxware.service.d/hardening.conf"
echo "  eBPF/XDP:     /opt/oxware/kernel/ebpf/xdp_filter.o"
echo "  Audit module: /dev/oxware_audit  (if compiled)"
echo "  Guard module: /dev/oxware_guard  (if compiled)"
echo ""
echo "  Next steps:"
echo "    1. sudo systemctl restart oxware"
echo "    2. sudo systemctl enable --now oxware-xdp"
echo "    3. Check AppArmor: sudo aa-status"
echo "    4. Check seccomp: sudo journalctl -u oxware | grep seccomp"
echo "    5. Monitor audit: sudo cat /dev/oxware_audit"
echo ""
if [[ $APPARMOR_MODE == "complain" ]]; then
  warn "AppArmor is in COMPLAIN mode. After testing, switch to enforce:"
  warn "  sudo aa-enforce /etc/apparmor.d/opt.oxware.backend.app"
fi
