# OXware Hypervisor

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.3-green.svg)](https://github.com/ShinnAsukha/oxware-hypervisor/releases)

OXware is an open-source KVM/QEMU hypervisor management platform built on Ubuntu/Debian. It provides a full-featured web UI for virtual machine lifecycle management, role-based access control, live monitoring, VNC console, networking, snapshots, security, and an AI assistant — making enterprise-grade virtualization accessible without a commercial license.

---

## Features

**VM Management**
- Full KVM/QEMU lifecycle: create, start, stop, pause, reboot, delete
- Clone VMs (full disk copy), bulk operations (start all / stop all / delete selected)
- CPU pinning, vCPU hot-plug, memory ballooning
- VM scheduling (start/stop at specific times), auto-start on host boot
- VM tagging, grouping, notes, and credentials vault
- OS image templates for rapid deployment
- **Import from ESXi / Proxmox / VirtualBox** — upload `.ova`, `.vmdk`, `.ovf`, `.qcow2`; auto-converted via `qemu-img`
- **KVM → KVM live migration** (zero-downtime between two OXware nodes via `virsh migrate --live`)
- **OVA export** — download any VM as a portable `.tar.gz` archive

**Console**
- VNC console via embedded noVNC in a dedicated browser window
- Pointer lock for seamless mouse capture, Ctrl+Alt+Del, fullscreen
- Web-based SSH terminal, SPICE info display

**Role-Based Access Control**

| Role | Permissions |
|---|---|
| `administrator` | Full access — users, settings, all VMs, system config |
| `operator` | VM management, storage, networking, system read-only |
| `viewer` | Read-only access to everything |
| `vm-user` | Sees only assigned VMs + summary dashboard; no creation or admin |

**Networking**
- IP pool management (CIDR allocation, static assignment), NAT and bridge modes
- Network QoS (per-VM bandwidth limits), libvirt DHCP static entries
- DNS watchdog with auto-repair, HAProxy load balancer integration

**Storage & Snapshots**
- qcow2 disk image management, snapshot create/revert/delete
- Auto-snapshot scheduler, backup to MinIO (S3-compatible) or local path
- SMART disk health monitoring

**Security**
- TOTP 2FA for all accounts, JWT authentication with refresh tokens
- CSRF double-submit protection, IP allowlist (per-IP whitelist)
- Per-VM and global nftables firewall rules managed via web UI
- IDS integration, security score dashboard, full audit log

**Monitoring**
- Live CPU, RAM, disk I/O, network I/O metrics with 60-second history
- Alert rules with Telegram, Discord, and email notifications
- Anomaly detection with auto-baseline, Prometheus metrics endpoint, uptime tracker

**AI Assistant**
- Natural-language VM creation, capacity forecasting, auto-scaler

**Integrations**
- LDAP / Active Directory SSO
- WiseCP and WHMCS provisioning modules
- Terraform provider
- Nginx reverse proxy + Let's Encrypt SSL management via web UI

**UI**
- Dark-theme single-page app, PWA (installable as desktop/mobile app)
- Multi-language: EN, TR, ES, DE, ZH
- Global search (Ctrl+K), keyboard shortcuts, drag-and-drop dashboard widgets
- Pentest tools tab (Nmap, port scan)

---

## Quick Start

```bash
git clone https://github.com/ShinnAsukha/oxware-hypervisor.git /opt/oxware-src
cd /opt/oxware-src
sudo bash install.sh
```

After installation, open **`https://<server-ip>:8006`** in your browser and complete the first-time setup wizard.

---

## Installation

### Method 1 — Bootable ISO (bare-metal, recommended)

```bash
cd build
sudo bash build-iso.sh
# Flash the resulting ISO to USB and boot the target machine
# Calamares installer guides the full setup
```

### Method 2 — Script on existing Ubuntu 22.04 LTS

```bash
git clone https://github.com/ShinnAsukha/oxware-hypervisor.git /opt/oxware-src
cd /opt/oxware-src
sudo bash install.sh
```

> **Requirements:** x86_64, VT-x/AMD-V enabled in BIOS, Ubuntu 22.04 LTS (Jammy), 2+ vCPUs, 2 GB+ RAM, 20 GB+ disk.

---

## First Login & Setup Wizard

1. Navigate to `https://<server-ip>:8006`.
2. Accept the self-signed certificate (or configure Let's Encrypt in Settings → SSL).
3. The setup wizard runs on first boot — set the admin password, hostname, and network mode.
4. Log in as `admin` and create additional users under **Users & Roles**.

---

## Architecture

```
Browser
  └── Single-page HTML/JS app (dark theme, PWA)
        ├── Flask REST API  (Python 3, SocketIO real-time)
        ├── JWT auth + RBAC middleware
        ├── libvirt / KVM  (VM lifecycle)
        ├── noVNC proxy    (VNC console)
        ├── nftables       (per-VM firewall)
        └── Nginx          (TLS termination, reverse proxy)
```

---

## ESXi / OVA Import & Migration

OXware can import VMs from any hypervisor that exports to standard formats, and supports zero-downtime live migration between OXware nodes.

### Import from ESXi / Proxmox / VirtualBox

| Format | Source | Method |
|---|---|---|
| `.ova` | VMware ESXi, VirtualBox, Proxmox | Upload via **OVA Import** button in dashboard |
| `.vmdk` | VMware ESXi / Workstation | Upload or SCP + manual convert |
| `.ovf` + `.vmdk` | VMware ESXi | Bundle as `.tar` then upload |
| `.qcow2` / `.raw` | Any KVM host | Direct import, no conversion |

**Via Web UI:** Dashboard → **↑ OVA Import** → select file → done.  
OXware extracts the archive, runs `qemu-img convert -O qcow2`, defines the VM in libvirt, and adds it to the dashboard automatically.

**Via SCP (faster for large disks):**
```bash
# Copy VMDK directly to OXware host
scp root@esxi:/vmfs/volumes/datastore/myvm.vmdk /var/lib/oxware/imports/

# Convert to qcow2
qemu-img convert -p -O qcow2 /var/lib/oxware/imports/myvm.vmdk \
    /var/lib/libvirt/images/myvm.qcow2
```

> **Downtime note:** Cross-hypervisor import (ESXi → OXware) always requires the VM to be powered off during export. Downtime = export + transfer + convert time (minutes to hours depending on disk size).

### KVM → KVM Live Migration (zero downtime)

Between two OXware nodes on the same network:

```bash
POST /api/vms/migrate
{
  "vm_id": "myvm",
  "target_host": "192.168.1.20",
  "protocol": "qemu+ssh"
}
```

Uses `virsh migrate --live --persistent`. The VM keeps running; typical downtime < 1 second at final memory sync.

### Export from OXware

```bash
POST /api/vms/{vm_id}/export
```

Downloads the VM as a `.tar.gz` (qcow2 disk + libvirt XML). Use for node-to-node moves or offline backups.

---

## Repair & Password Reset

```bash
# Repair services after unexpected failure or reboot
sudo bash repair.sh

# Reset the admin password
sudo bash repair.sh --reset-password
```

---

## Contributing

1. Fork the repository and create a feature branch.
2. Follow PEP 8 for Python code; use `eslint` for frontend JS.
3. Open a pull request with a clear description of the change.
4. All PRs require at least one review before merge.

Bug reports and feature requests are welcome via [GitHub Issues](https://github.com/ShinnAsukha/oxware-hypervisor/issues).

---

## License

[MIT License](LICENSE) — © 2024 Ada Gürsoy / ShinnAsukha
