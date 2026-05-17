# OXware Hypervisor — ISO Builder

Builds a bootable ISO with the **Calamares graphical installer** (Qt5/OXware branded) and the **OXware Hypervisor** stack pre-installed in the squashfs live environment.

---

## Requirements

| Requirement         | Value                        |
|---------------------|------------------------------|
| Host OS             | Ubuntu 22.04+ or Debian 12   |
| Free disk space     | ≥ 15 GB                      |
| RAM                 | ≥ 4 GB recommended           |
| Privileges          | `root` / `sudo`              |
| Network             | Required (packages downloaded during build) |

---

## Build

```bash
sudo bash build/build-iso.sh
```

The script:
1. Downloads Ubuntu 22.04 Server ISO (cached at `/tmp/`)
2. Extracts and patches the squashfs (disables Subiquity / cloud-init / console-conf)
3. Installs Calamares + X11 + Qt5 in squashfs via chroot
4. Copies OXware branding, Calamares configs, and headless installer
5. Repacks squashfs and generates a bootable hybrid ISO

Output:
```
OXware-Hypervisor-<version>-amd64.iso   (~1.5 GB)
OXware-Hypervisor-<version>-amd64.iso.sha256
```

---

## Write to USB / Disk

**Linux:**
```bash
sudo dd if=OXware-Hypervisor-*.iso of=/dev/sdX bs=4M status=progress && sync
```

**Windows:** Use [Rufus](https://rufus.ie) or [Ventoy](https://ventoy.net).

---

## Boot & Install

1. Boot the server from USB/ISO.
2. OXware graphical installer (Calamares) launches automatically.
3. Follow the wizard:
   - **Locale & Keyboard** — Turkish default, changeable
   - **Disk** — Erase full disk (required)
   - **User** — Admin username & password
   - **Summary** — Review and confirm
4. Installation runs headlessly in the background (~5-15 min).
5. After reboot, the OXware web UI is available at `https://<server-ip>:8006`.

---

## Automated Build via GitHub Actions

Push a git tag to trigger a full build and attach the ISO to a GitHub Release:

```bash
git tag v2.0.1 && git push origin v2.0.1
```

The workflow (`.github/workflows/build-iso.yml`) runs on `ubuntu-22.04`, builds the ISO, and uploads it as a release asset.

For manual builds without a tag (`workflow_dispatch`), the ISO is uploaded as a workflow artifact.

---

## Directory Layout

```
build/
├── build-iso.sh                   # Main build script — run this as root
├── VERSION                        # Auto-incremented patch version
│
├── calamares/                     # Calamares graphical installer config
│   ├── settings.conf              # Installer sequence & branding ref
│   ├── oxware-xorg.conf           # Minimal Xorg config (modesetting)
│   ├── branding/
│   │   └── oxware/
│   │       ├── branding.desc      # Colors, product name, logo refs
│   │       └── show.qml           # QML slideshow (4 slides, Türkçe)
│   └── modules/
│       ├── welcome.conf
│       ├── locale.conf            # tr_TR.UTF-8 default
│       ├── keyboard.conf
│       ├── partition.conf         # Erase-disk mode only
│       ├── users.conf
│       ├── summary.conf
│       ├── finished.conf
│       └── oxware_install/
│           ├── module.desc        # Calamares Python job declaration
│           └── main.py            # Reads globalStorage → JSON → install.py --headless
│
├── installer/
│   ├── install.py                 # Headless installer backend (called by Calamares job)
│   └── oxware-start.sh            # xinit launcher: starts X11 → Calamares on tty1
│
├── tui-installer/
│   └── installer.py               # Legacy curses TUI (not used — kept for reference)
│
├── rootfs/
│   └── etc/
│       ├── motd                   # Live-boot welcome message
│       └── systemd/system/
│           ├── oxware-installer.service   # Launches oxware-start.sh on tty1
│           └── oxware.service             # OXware backend on installed system
│
└── grub/
    └── grub.cfg                   # GRUB boot menu template
```

---

## Installer Architecture

```
Boot ISO
  └── systemd: oxware-installer.service
        └── /opt/oxware-installer/oxware-start.sh
              └── xinit /usr/bin/calamares -- :0 vt1
                    └── Calamares (Qt5, OXware branding)
                          ├── Show: welcome / locale / keyboard / partition / users / summary
                          ├── Exec: oxware_install (Python job)
                          │         └── install.py --headless /tmp/oxware-install-config.json
                          │               └── debootstrap + KVM/libvirt + GRUB + OXware service
                          └── Show: finished → reboot
```

The `tui-installer/` directory is **not used** in the current build. Only `installer/install.py` is embedded in the ISO (called headlessly by the Calamares job module).
