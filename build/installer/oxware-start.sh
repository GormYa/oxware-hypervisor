#!/bin/bash
# OXware graphical installer launcher — runs on tty1 as root
# Starts X11 and launches Calamares with OXware branding

export DISPLAY=:0
export HOME=/root
export XDG_RUNTIME_DIR=/tmp/xdg-runtime-oxware
export XAUTHORITY=/root/.Xauthority

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Wait for udev / block devices to settle
udevadm settle --timeout=10 2>/dev/null || true

# Framebuffer / video: try modesetting first, then vesa
XORG_CONF=""
if [ -f /etc/X11/oxware-xorg.conf ]; then
    XORG_CONF="-config /etc/X11/oxware-xorg.conf"
fi

# Launch Calamares inside xinit
exec xinit /usr/bin/calamares --debug -- :0 -nolisten tcp vt1 $XORG_CONF
