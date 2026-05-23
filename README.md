# OXware Hypervisor

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.4-brightgreen.svg)](https://github.com/ShinnAsukha/oxware-hypervisor/releases)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%2022.04%20%7C%20Debian%2012-orange.svg)]()
[![KVM](https://img.shields.io/badge/hypervisor-KVM%2FQEMU-red.svg)]()
[![Python](https://img.shields.io/badge/python-3.10%2B-blue.svg)]()
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**OXware** is a full-featured, open-source KVM/QEMU hypervisor management platform. It replaces VMware ESXi and Proxmox VE with a modern dark-theme web UI, REST API, real-time monitoring, role-based access control, VNC console, AI assistant, and more — with zero licensing fees.

> Built for bare-metal servers, cloud VPS, and on-prem homelab. One command installs everything.

> **v2.4 (2026-05):** Bridge IP isolation, cloud-init static IP injection, RAM hot-increase (stop/restart), SFTP ESXi VMDK browser + auto-import, monitoring stagger fix, subnet calculator, network DHCP live edit, natural language command confirmation, import name dedup, VM-to-network auto-connect.

---

## Table of Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [First Login & Setup](#first-login--setup)
- [Architecture](#architecture)
- [Configuration](#configuration)
- [API](#api)
- [Role-Based Access Control](#role-based-access-control)
- [ESXi / OVA Import & Migration](#esxi--ova-import--migration)
- [Networking](#networking)
- [Storage & Snapshots](#storage--snapshots)
- [Security](#security)
- [Monitoring & Alerts](#monitoring--alerts)
- [AI Assistant](#ai-assistant)
- [Integrations](#integrations)
- [Repair & Maintenance](#repair--maintenance)
- [Comparison](#comparison)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Features

### Virtual Machine Management
- **Full KVM/QEMU lifecycle** — create, start, stop, pause, resume, reboot, delete, force-kill
- **Clone VMs** — full disk copy with automatic name deduplication
- **Bulk operations** — start all / stop all / delete selected VMs in one click
- **CPU pinning** — bind vCPUs to specific physical cores for NUMA-aware workloads
- **vCPU hot-plug & memory ballooning** — reduce RAM without downtime; increase RAM auto-stops + resizes + restarts VM
- **VM scheduling** — start/stop VMs at specific times via cron-like rules
- **Auto-start on boot** — mark VMs to start automatically after host reboot
- **Tags & groups** — organize VMs with custom tags, filter/search the dashboard
- **Notes & credentials vault** — per-VM encrypted notes and SSH key storage
- **OS image templates** — rapid deployment from pre-built qcow2 templates
- **Import from ESXi / Proxmox / VirtualBox** — `.ova`, `.vmdk`, `.ovf`, `.qcow2`, `.raw`, `.zip`; auto name-conflict dedup
- **SFTP/ESXi VMDK browser** — browse ESXi datastore directories directly in UI; one-click download + convert + import
- **Import VM → auto-connect network** — choose which libvirt network to connect the imported VM to; no manual XML edit
- **cloud-init static IP injection** — set real routable IP, gateway, netmask, DNS at VM creation; no DHCP needed
- **KVM → KVM live migration** — zero-downtime migration between two OXware nodes
- **OVA export** — download any VM as a portable `.tar.gz` archive

### Console & Remote Access
- **Multi-console type selection** — choose noVNC (graphical VNC), xterm.js serial (virsh console via PTY), or SPICE for each VM
- **noVNC console** — embedded in a dedicated browser tab; no client software needed
- **xterm.js serial console** — direct virsh console over WebSocket; works headless (no GUI required on guest)
- **SPICE support** — connection info and one-click open for SPICE-capable VMs
- **Clipboard paste** — paste into any console via Ctrl+Shift+V, right-click, or toolbar button
- **Auto TLS** — VNC WebSocket traffic encrypted; self-signed cert auto-generated at first start
- **Pointer lock** — seamless mouse capture inside the VNC window
- **Ctrl+Alt+Del** — send keyboard shortcuts to VM
- **Fullscreen mode** — native browser fullscreen for the console
- **Host shell console** — root PTY shell on the hypervisor; xterm.js with paste support
- **SPICE info** — display connection info for SPICE-capable clients

### Role-Based Access Control
- Four built-in roles: `administrator`, `operator`, `viewer`, `vm-user`
- `vm-user` role — sees only assigned VMs; can start/stop/console their own VMs
- Per-user VM assignment with deny-by-default enforcement
- LDAP / Active Directory SSO for enterprise environments
- TOTP 2FA for all accounts
- Session management — view and revoke active sessions from the web UI

### Networking
- **Detailed network page** — 5-tab view: Virtual Networks, Host Interfaces, DHCP Leases, Routing Table, Bridge & IP Isolation
- **Host interface stats** — CSS-styled type badges (ethernet/bridge/virtual/bond/vlan/tunnel/wifi), speed, duplex, RX/TX bytes+packets
- **DHCP live leases** — browse all active DHCP assignments with hostname, MAC, expiry
- **Routing table** — live kernel route table view via `ip route`
- **Network DHCP live edit** — edit Gateway / Netmask / DHCP range of any virtual network from UI; auto stop→redefine→start
- **Bridge IP isolation** — one-click setup of `oxbr0` Linux bridge with physical NIC as member; VMs get real upstream IPs
- **IP pool management (IPAM)** — CIDR-based allocation, static assignment, NAT and bridge modes
- **Subnet calculator** — built-in CIDR calculator in IPAM page: network/broadcast/host range/count/mask/wildcard/class/RFC1918
- **DHCP static entries** — bind VM MAC → IP via libvirt dnsmasq
- **Per-VM firewall** — nftables rules managed via web UI (allow/deny by port, protocol, source)
- **Network QoS** — per-VM bandwidth limits (ingress/egress); manual load button (no auto-freeze)
- **BGP tunneling** — peer management (add/remove BGP peers) via UI and API
- **DNS watchdog** — monitors resolution health, auto-repairs broken dnsmasq
- **HAProxy load balancer** — configure L4/L7 backends from the UI
- **VLAN support** — tag-based VLAN isolation for multi-tenant setups
- **Topology view** — interactive network graph showing VM ↔ network ↔ host relationships
- **Network speedtest** — built-in latency + download benchmark to 12 servers (4× Turkey, 8× international)

### Storage & Snapshots
- **qcow2 image management** — create, resize, move disk images
- **Disk type detection** — auto-detect NVMe/SSD/HDD/virtual with badge in UI
- **Disk backup** — copy VM disk to local path with path traversal protection
- **Disk wipe** — secure zero-fill + delete with double confirmation; irreversible action guard
- **Snapshot create / revert / delete** — live snapshots for running VMs
- **Auto-snapshot scheduler** — periodic snapshots with configurable retention
- **Backup to MinIO / S3** — scheduled off-host backups to any S3-compatible store
- **SFTP/SSH backup** — transfer backups to remote servers via paramiko; test connection from UI
- **Local backup path** — rsync to NFS, USB, or another local mount
- **SMART health monitoring** — disk health alerts before failures
- **ISO library** — upload, list, and attach ISO images; auto-scans `/tmp` and `/var/lib/libvirt/images`

### Security
- **JWT authentication** — short-lived access tokens + refresh tokens, auto-rotation
- **TOTP 2FA** — per-account TOTP; mandatory enforcement configurable per role
- **CSRF protection** — double-submit cookie pattern on all state-changing endpoints
- **IP allowlist** — restrict dashboard access to specific CIDRs
- **Auto TLS cert** — self-signed RSA 4096 certificate auto-generated at startup
- **Security audit log** — every login, VM action, config change, and API call logged
- **Security score dashboard** — live posture rating with actionable recommendations
- **IDS integration** — Suricata/Snort alert ingestion
- **Rate limiting** — per-IP request throttling on auth endpoints
- **Secrets vault** — encrypted per-VM credential storage
- **Role enforcement on AI** — `vm-user` role blocked from OXY AI (prevents information disclosure)
- **Path traversal protection** — all disk paths validated with `os.path.realpath()` + allowlist
- **No PDF export** — export functionality removed; avoids client-side data exposure vulnerabilities

### Monitoring & Observability
- **Live metrics** — CPU %, RAM %, disk I/O MB/s, network RX/TX MB/s; no blocking sleep
- **60-second history charts** — sparkline graphs per VM
- **Alert rules** — threshold-based triggers (CPU > 90 %, disk full, VM down)
- **Notifications** — Telegram bot, Discord webhook, SMTP email
- **Anomaly detection** — rolling baseline, auto-alert on deviation
- **Prometheus endpoint** — `/metrics` exposes all VM and host stats for Grafana
- **Uptime tracker** — per-VM uptime history, SLA calculation
- **Node summary** — host CPU, RAM, disk, load, network overview
- **İzleme+ staggered loading** — 5-tier deferred load prevents UI freeze; QoS/Trend/Migration load on demand only
- **Network speedtest** — server-to-internet latency + download test; 12 servers across 4 continents

### AI Assistant
- **Natural-language VM creation** — "Create a 4-core Ubuntu server with 8 GB RAM" → done
- **Natural-language commands with confirmation** — AI parses intent (start/stop/list/snapshot); confirmation dialog for destructive actions; direct execution after confirm
- **Capacity forecasting** — predicts when resources will run out based on growth trends
- **Auto-scaler** — automatically start/stop VMs based on load policies
- **Recommended actions** — AI suggests optimizations (right-sizing, snapshot scheduling)
- **vm-user AI block** — `vm-user` role cannot access OXY AI; prevents host information disclosure

### Integrations
- **LDAP / Active Directory** — SSO login, group-to-role mapping
- **WiseCP** — provisioning module for hosting control panel automation
- **WHMCS** — VM lifecycle hooks for billing integration
- **Terraform provider** — IaC-driven VM provisioning
- **Nginx + Let's Encrypt** — manage reverse proxy and SSL certs from the UI
- **MinIO / S3** — backup and ISO storage
- **Webhook system** — fire HTTP callbacks on VM events (start, stop, create, delete)
- **Custom hooks** — pre/post scripts for any VM lifecycle event

### UI & UX
- **Dark-theme single-page app** — no page reloads, instant navigation
- **PWA** — installable as a desktop or mobile app (Add to Home Screen)
- **Multi-language** — English, Turkish, Spanish, German, Chinese (easily extensible)
- **Global search** — `Ctrl+K` searches VMs, pages, settings
- **Keyboard shortcuts** — create VM, navigate panels, toggle fullscreen
- **Mobile responsive** — full functionality on phone/tablet screens
- **Interactive API explorer** — browse and test all endpoints at `/api/docs`

---

## Screenshots

> Dashboard, VM detail, console, monitoring, and networking views available at [oxware.top](https://oxware.top).

---

## Quick Start

```bash
# Clone and install on Ubuntu 22.04 LTS
git clone https://github.com/ShinnAsukha/oxware-hypervisor.git /opt/oxware-src
cd /opt/oxware-src
sudo bash install.sh
```

Then open **`https://<server-ip>:8006`** — the setup wizard runs on first boot.

---

## Installation

### Method 1 — Bootable ISO (bare-metal, recommended)

Build a bootable installer ISO that runs the Calamares GUI installer on boot:

```bash
cd build
sudo bash build-iso.sh
# Flash the resulting OXware-Hypervisor-*.iso to a USB drive
# Boot the target machine from USB
# Calamares guides the full installation
```

The build script automatically finds any existing Debian live ISO in `/tmp/` to avoid re-downloading. If no cached ISO exists it tries five mirrors in order (official `cdimage.debian.org` first).

> **Requirements for ISO build:** 15 GB free disk, `xorriso`, `squashfs-tools`, `wget`

### Method 2 — Script on existing Ubuntu 22.04 LTS

```bash
git clone https://github.com/ShinnAsukha/oxware-hypervisor.git /opt/oxware-src
cd /opt/oxware-src
sudo bash install.sh
```

The installer:
1. Installs QEMU/KVM, libvirt, Python 3, Nginx, noVNC, and all dependencies
2. Creates system user `oxware`, sets up directories under `/var/lib/oxware/` and `/etc/oxware/`
3. Writes a default config to `/etc/oxware/oxware.conf`
4. Installs the OXware Flask app as a `systemd` service (`oxware.service`)
5. Configures Nginx as a reverse proxy on port 8006 with a self-signed TLS cert
6. Generates a random JWT secret and stores it in `/etc/oxware/jwt_secret.key`

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores, VT-x/AMD-V | 4+ cores |
| RAM | 2 GB | 8 GB+ |
| Disk | 20 GB | 100 GB+ (for VM images) |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |
| Network | 1 NIC | 2 NICs (mgmt + VM traffic) |

---

## First Login & Setup

1. Navigate to `https://<server-ip>:8006`
2. Accept the self-signed certificate warning (or configure Let's Encrypt in **Settings → SSL**)
3. The **Setup Wizard** runs on first access — set admin password, hostname, network mode
4. Log in as `admin`
5. Go to **Users & Roles** to create additional accounts
6. Go to **Storage** to upload ISO images
7. Click **+ Create VM** to launch your first virtual machine

**Default admin account:** set during the wizard (no default password stored)

---

## Architecture

```
                        ┌──────────────────────────────────┐
                        │          Browser Client           │
                        │   Single-page HTML/JS (dark UI)  │
                        │   PWA · Multi-lang · Ctrl+K       │
                        └──────────────┬───────────────────┘
                                       │ HTTPS + WSS (port 8006)
                        ┌──────────────▼───────────────────┐
                        │           Nginx / TLS             │
                        │  Reverse proxy · Let's Encrypt   │
                        └──────────────┬───────────────────┘
                                       │
                        ┌──────────────▼───────────────────┐
                        │       Flask + Flask-SocketIO      │
                        │   REST API · JWT · RBAC · Events  │
                        │   Rolling perf cache · Rate limit │
                        └────┬──────┬───────┬──────────────┘
                             │      │       │
              ┌──────────────▼──┐ ┌─▼─────┐ ┌▼──────────────┐
              │  libvirt / KVM  │ │ nft-  │ │  System tools  │
              │  QEMU domains   │ │ ables  │ │  ip, dnsmasq   │
              │  VNC proxy      │ │ fw    │ │  Nginx, HAProxy│
              └─────────────────┘ └───────┘ └───────────────┘
                        │
              ┌──────────▼─────────────────────────────────┐
              │              Storage layer                   │
              │  /var/lib/oxware/disks/   (qcow2 images)    │
              │  /var/lib/oxware/isos/    (ISO library)      │
              │  /var/lib/oxware/backups/ (snapshots, S3)   │
              └────────────────────────────────────────────┘
```

**Key design decisions:**
- **No external message broker** — SocketIO handles real-time events without Redis/RabbitMQ
- **No separate database** — VM state lives in libvirt XML; users/config in JSON files under `/var/lib/oxware/`
- **Rolling perf cache** — `/api/vms/<id>/perf` uses a per-VM sample cache; zero blocking sleeps
- **3-second list cache** — `list_vms()` is cached with automatic invalidation on mutations

---

## Configuration

Config file: `/etc/oxware/oxware.conf`

```ini
[server]
host     = 0.0.0.0
port     = 8006
ssl      = true
ssl_cert = /etc/oxware/ssl/oxware.crt
ssl_key  = /etc/oxware/ssl/oxware.key

[storage]
data_dir    = /var/lib/oxware
iso_dir     = /var/lib/oxware/isos
disk_dir    = /var/lib/oxware/disks
backup_dir  = /var/lib/oxware/backups

[vnc]
start_port    = 5900
end_port      = 5999
websocket_port = 6080

[libvirt]
uri = qemu:///system

[logging]
log_dir = /var/log/oxware
level   = INFO
```

**SSL note:** If `ssl_cert` or `ssl_key` files don't exist at startup, OXware automatically generates a self-signed RSA 4096 certificate valid for 10 years and saves it to `/etc/oxware/ssl/`. No manual `openssl` command needed.

**JWT secret:** Auto-generated as a 128-char hex token on first run and persisted to `/etc/oxware/jwt_secret.key`. Rotating this file logs out all active sessions.

---

## API

OXware exposes a full REST API. All endpoints require a JWT Bearer token (or session cookie).

```bash
# 1. Authenticate
curl -k -X POST https://host:8006/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"yourpass"}'
# → {"token": "eyJ..."}

# 2. Use the token
curl -k https://host:8006/api/vms \
  -H "Authorization: Bearer eyJ..."
```

**Interactive API explorer** — navigate to `https://<host>:8006/api/docs` to browse all 23+ endpoints with live request firing, parameter schemas, and example responses.

### Key endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/auth/login` | Get JWT token |
| `GET` | `/api/vms` | List all VMs |
| `POST` | `/api/vms` | Create VM |
| `GET` | `/api/vms/<id>` | VM details |
| `DELETE` | `/api/vms/<id>` | Delete VM |
| `POST` | `/api/vms/<id>/start` | Start VM |
| `POST` | `/api/vms/<id>/stop` | Stop VM |
| `POST` | `/api/vms/<id>/pause` | Pause VM |
| `POST` | `/api/vms/<id>/reboot` | Reboot VM |
| `POST` | `/api/vms/<id>/clone` | Clone VM |
| `GET` | `/api/vms/<id>/perf` | Live CPU/RAM/IO metrics |
| `GET` | `/api/vms/<id>/snapshots` | List snapshots |
| `POST` | `/api/vms/<id>/snapshots` | Create snapshot |
| `POST` | `/api/vms/<id>/console/start` | Get VNC port |
| `POST` | `/api/vms/migrate` | Live migration |
| `GET` | `/api/users` | List users |
| `GET` | `/metrics` | Prometheus metrics |

---

## Role-Based Access Control

| Role | VM Control | User Mgmt | Settings | Network | Storage |
|------|-----------|-----------|----------|---------|---------|
| `administrator` | ✅ All VMs | ✅ Full | ✅ Full | ✅ Full | ✅ Full |
| `operator` | ✅ All VMs | ❌ | ⚠️ Read-only | ✅ Full | ✅ Full |
| `viewer` | 👁 Read-only | ❌ | ❌ | 👁 Read-only | 👁 Read-only |
| `vm-user` | ✅ Assigned VMs only | ❌ | ❌ | ❌ | ❌ |

**vm-user** can start, stop, reboot, pause, resume, and open the VNC console for VMs explicitly assigned to them. Attempting to access any other VM returns 403.

---

## ESXi / OVA Import & Migration

OXware imports VMs from any hypervisor that exports to standard formats, and supports zero-downtime live migration between OXware nodes.

### Import from ESXi / Proxmox / VirtualBox

| Format | Source | Method |
|--------|--------|--------|
| `.ova` | VMware ESXi, VirtualBox, Proxmox | Upload via **↑ OVA Import** button |
| `.vmdk` | VMware ESXi / Workstation | Upload, SCP, or **SFTP browser** |
| `.ovf` + `.vmdk` | VMware ESXi | Bundle as `.tar` or use SFTP browser |
| `.zip` | VMware Workstation VM folder | Upload as `.zip` — auto-extracted |
| `.qcow2` / `.raw` | Any KVM host | Direct import, no conversion needed |

**Via Web UI:** Dashboard → **↑ OVA Import** → select file + target network → OXware extracts the archive, runs `qemu-img convert -O qcow2`, auto-deduplicates name on conflict, defines the domain in libvirt connected to the chosen network.

**Via SFTP Browser (ESXi direct, new in v2.4):** Settings → Backup → SFTP tab → enter ESXi host/credentials → **📂 Dosyaları Listele** → navigate datastore → click **⬇ İndir+Import** on any VMDK. OXware downloads, converts, and imports automatically. Choose target network before download.

**Via SCP (faster for large disks):**

```bash
# Copy VMDK from ESXi datastore
scp root@esxi-host:/vmfs/volumes/datastore1/myvm/myvm.vmdk \
    root@oxware-host:/var/lib/oxware/imports/

# Convert on OXware host
qemu-img convert -p -f vmdk -O qcow2 \
    /var/lib/oxware/imports/myvm.vmdk \
    /var/lib/oxware/disks/myvm.qcow2

# Register via API
curl -k -X POST https://localhost:8006/api/vms/import \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"name":"myvm","disk":"/var/lib/oxware/disks/myvm.qcow2","vcpus":4,"memory_mb":8192}'
```

> **Downtime note:** Cross-hypervisor import (ESXi → OXware) requires the VM to be powered off during export. Total downtime = export time + transfer time + convert time (minutes to hours depending on disk size and link speed).

### KVM → KVM Live Migration (zero downtime)

Between two OXware nodes on the same network:

```bash
POST /api/vms/migrate
{
  "vm_id": "<vm-uuid>",
  "target_host": "192.168.1.20",
  "protocol": "qemu+ssh"
}
```

Internally uses `virsh migrate --live --persistent --compressed`. The VM keeps running during transfer; typical stop-and-copy phase < 1 second at final memory sync.

**Requirements:**
- Both nodes must have shared or equivalent storage (NFS, Ceph, or pre-copied disk)
- Passwordless SSH from source to target for the `libvirt-qemu` user
- Same libvirt version on both nodes recommended

### Export from OXware

```bash
POST /api/vms/{vm_id}/export
```

Downloads the VM as a `.tar.gz` containing the qcow2 disk image and libvirt XML definition. Use for node-to-node moves or offline archive.

---

## Networking

### IP Pool Management

Create CIDR pools and assign IPs to VMs:

```bash
POST /api/network/pools
{
  "name": "prod-net",
  "cidr": "10.0.1.0/24",
  "gateway": "10.0.1.1",
  "dns": ["8.8.8.8", "1.1.1.1"]
}
```

### NAT & Bridge

- **NAT mode** — VMs share the host's public IP via MASQUERADE; public ports forwarded via nftables DNAT rules managed by OXware
- **Bridge mode** — VMs appear directly on the physical network; assign IPs from upstream DHCP or static

### Per-VM Firewall

Each VM has its own nftables chain. Rules are applied via the **Güvenlik Duvarı** (Firewall) panel:

```bash
POST /api/network/firewall/<vm_id>
{
  "rules": [
    {"action":"accept","proto":"tcp","dport":22},
    {"action":"accept","proto":"tcp","dport":443},
    {"action":"drop","proto":"tcp"}
  ]
}
```

---

## Storage & Snapshots

### Disk Images

All VM disks are stored as qcow2 images under `/var/lib/oxware/disks/`. The format supports:
- Thin provisioning (actual file size grows on write)
- Copy-on-write snapshots with zero initial overhead
- AES-256 encryption (configure per-VM in the web UI)

### Snapshots

```bash
# Create snapshot via API
POST /api/vms/<id>/snapshots
{"name": "before-upgrade", "description": "Pre-upgrade baseline"}

# Revert to snapshot
POST /api/vms/<id>/snapshots/<snap_id>/revert

# Delete snapshot
DELETE /api/vms/<id>/snapshots/<snap_id>
```

Auto-snapshot scheduler is in **Depolama → Otomatik Snapshot**.

### Backups

Configure S3/MinIO backup target in **Entegrasyonlar → S3**:

```json
{
  "endpoint": "https://minio.example.com",
  "bucket": "oxware-backups",
  "access_key": "...",
  "secret_key": "..."
}
```

---

## Security

### TLS

On startup, OXware checks for `/etc/oxware/ssl/oxware.crt` and `/etc/oxware/ssl/oxware.key`. If either is missing, it automatically generates a self-signed RSA 4096 certificate (10-year validity). To use a real certificate:

```bash
# Option A: Let's Encrypt (managed via web UI Settings → SSL)
# Option B: Manual placement
cp fullchain.pem /etc/oxware/ssl/oxware.crt
cp privkey.pem   /etc/oxware/ssl/oxware.key
systemctl restart oxware
```

### 2FA

Enable TOTP in **Güvenlik → İki Faktörlü Doğrulama**. Scan the QR code with any TOTP app (Google Authenticator, Authy, etc.). Once enabled, login requires both password and 6-digit TOTP code.

### Audit Log

Every action is logged with timestamp, user, source IP, and payload. Access via **Güvenlik → Denetim Günlüğü** or the API:

```bash
GET /api/audit?limit=100&user=admin
```

---

## Monitoring & Alerts

### Prometheus Integration

OXware exposes Prometheus-compatible metrics at `/metrics`:

```
oxware_vm_cpu_percent{vm="my-server"} 23.4
oxware_vm_ram_percent{vm="my-server"} 61.2
oxware_vm_state{vm="my-server"} 1
oxware_host_load1 0.87
```

Import the OXware Grafana dashboard from `/docs` for pre-built panels.

### Alert Rules

Configure thresholds in **İzleme+ → Alarm Kuralları**:

```json
{
  "metric": "cpu_percent",
  "operator": ">",
  "threshold": 90,
  "duration_seconds": 300,
  "notify": ["telegram", "email"]
}
```

---

## AI Assistant

The AI assistant (`AI Asistan` panel) uses an LLM to:

- **Create VMs from natural language** — "Create two Ubuntu 22.04 VMs with 4 cores and 8 GB RAM for a HA pair"
- **Forecast capacity** — "When will I run out of RAM at current growth rate?"
- **Optimize** — "Which VMs have been idle for 7 days? Suggest shutdown"
- **Auto-scale** — define CPU/RAM thresholds that trigger VM start/stop automatically

---

## Integrations

### LDAP / Active Directory

Configure in **Güvenlik → LDAP**:

```json
{
  "server": "ldap://dc.company.com",
  "base_dn": "dc=company,dc=com",
  "bind_dn": "cn=oxware,ou=svc,dc=company,dc=com",
  "bind_pw": "...",
  "user_filter": "(sAMAccountName={username})",
  "group_map": {
    "CN=Hypervisor-Admins,OU=Groups": "administrator",
    "CN=Hypervisor-Ops,OU=Groups": "operator"
  }
}
```

### Webhooks

Fire HTTP callbacks on VM events:

```bash
POST /api/integrations/webhooks
{
  "url": "https://your-app.com/vm-events",
  "events": ["vm.started", "vm.stopped", "vm.created", "vm.deleted"],
  "secret": "hmac-secret-for-signature-verification"
}
```

---

## Repair & Maintenance

```bash
# Repair services after unexpected failure or reboot
sudo bash repair.sh

# Reset the admin password
sudo bash repair.sh --reset-password

# View service status
systemctl status oxware

# View logs
journalctl -u oxware -f

# Manual restart
systemctl restart oxware
```

Config, data, and logs:

| Path | Contents |
|------|----------|
| `/etc/oxware/oxware.conf` | Main configuration |
| `/etc/oxware/ssl/` | TLS certificate and key |
| `/var/lib/oxware/` | Disks, ISOs, backups, user data |
| `/var/log/oxware/oxware.log` | Application log |
| `/var/log/oxware/` | All OXware logs |

---

## Comparison

| Feature | OXware | Proxmox VE | VMware ESXi |
|---------|--------|-----------|------------|
| License | MIT (free) | AGPL / paid subscription | Commercial |
| KVM/QEMU backend | ✅ | ✅ | ❌ (proprietary) |
| Web UI | ✅ Dark, modern SPA | ✅ | ✅ |
| REST API | ✅ Full | ✅ | ✅ |
| AI Assistant | ✅ | ❌ | ❌ |
| Built-in 2FA | ✅ | ✅ | ⚠️ (enterprise) |
| Live migration | ✅ | ✅ | ✅ (vMotion) |
| OVA/VMDK import | ✅ | ✅ | ✅ |
| Auto TLS cert | ✅ | ✅ | ⚠️ |
| IP pool / IPAM | ✅ | ✅ | ⚠️ |
| Per-VM firewall | ✅ | ✅ | ⚠️ |
| Prometheus metrics | ✅ | ✅ | ⚠️ (plugin) |
| LDAP / AD SSO | ✅ | ✅ | ✅ |
| WiseCP / WHMCS | ✅ | ⚠️ (3rd party) | ❌ |
| Self-hosted | ✅ | ✅ | ✅ |

---

## Troubleshooting

**Web UI returns 502 / ERR_CONNECTION_REFUSED**
```bash
systemctl restart oxware nginx
journalctl -u oxware -n 50
```

**VMs not showing in dashboard**
```bash
virsh list --all            # verify libvirt sees them
systemctl restart libvirtd
```

**VNC console shows black screen**
- VM may still be booting — wait 30 seconds
- Check VNC port: `virsh dumpxml <vm> | grep vnc`
- Ensure firewall allows port range 5900–5999 on loopback

**Cannot start a VM: "domain already exists"**
- This is handled automatically — OXware appends `-2`, `-3` etc. to cloned names
- If it persists: `virsh undefine <name>` then retry

**ISO download fails in build-iso.sh**
- The build script tries 5 mirrors in order
- If all fail: `wget -O /tmp/debian-12-live-standard-amd64.iso <url>` manually, then re-run the script — it will detect the cached ISO and skip download

**SSL cert warning in browser**
- Expected on first run with self-signed cert
- To suppress: configure Let's Encrypt in **Settings → SSL** (requires public domain + open port 80)
- Or import the cert at `/etc/oxware/ssl/oxware.crt` into your browser's trust store

**Forgot admin password**
```bash
sudo bash repair.sh --reset-password
```

---

## Changelog

### v2.4 — 2026-05

**New features:**
- **Bridge IP isolation** — `oxbr0` Linux bridge setup from UI (Network → Bridge & IP İzolasyonu); VMs get real upstream IPs
- **cloud-init static IP** — set static IP/gateway/netmask/DNS at VM creation; injected as `network-config v2` YAML via NoCloud ISO
- **RAM hot-increase** — requesting RAM above current max: VM stops → XML updated → VM restarts; below max uses balloon
- **SFTP ESXi browser** — navigate ESXi datastore directories in UI; one-click download → qemu-img convert → virsh define
- **Import VM → network** — choose target libvirt network for OVA upload and SFTP import; eliminates manual post-import XML edit
- **Import name dedup** — auto-appends `-1`, `-2`... when imported VM name conflicts with existing domain
- **Subnet calculator** — built-in CIDR calculator in IPAM page (network, broadcast, host range, count, mask, wildcard, class, binary)
- **Network DHCP live edit** — edit Gateway/Netmask/DHCP start-end from network edit modal; auto stop→redefine→start
- **Natural language confirm** — NL commands requiring confirmation show Onayla button; `force_execute` bypasses re-parse
- **Monitoring stagger** — İzleme+ loads in 5 deferred tiers; QoS/Trend/Migration are manual-only (no freeze)

**Bug fixes:**
- Kurulum rehberi button now opens modal (inline `display:none` removed)
- Network page badges use CSS classes instead of inline styles (`.net-forward-badge`, `.iface-card-type`, etc.)
- `vm-user` role blocked from all `/api/ai/*` endpoints
- PDF export removed from all paths (security hardening)
- All AdaOS → OXware references updated in docstrings, log names, paths

---

## Contributing

1. Fork the repository and create a feature branch (`git checkout -b feat/my-feature`)
2. Follow **PEP 8** for Python; standard ES2020 for frontend JS
3. Test your change against a local KVM host
4. Open a pull request with a description of what changed and why
5. All PRs require at least one review before merge

Bug reports and feature requests → [GitHub Issues](https://github.com/ShinnAsukha/oxware-hypervisor/issues)

---

## License

[MIT License](LICENSE) — © 2026 Ada Gürsoy

Free to use, modify, and distribute. Commercial use permitted. Attribution appreciated.
