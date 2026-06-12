# OXware Hypervisor

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.7.2-brightgreen.svg)](https://github.com/ShinnAsukha/oxware-hypervisor/releases)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%2022.04+%20%7C%20Debian%2012+-orange.svg)]()
[![KVM](https://img.shields.io/badge/hypervisor-KVM%2FQEMU-red.svg)]()

A KVM/QEMU management platform for single-node and small-cluster deployments. Built on libvirt, Python/Flask, noVNC, and nftables. Provides a web UI, REST API, and CLI for VM lifecycle, networking, storage, and access control.

This project is **early-stage and self-funded**. It is suitable for homelab, lab environments, and small production workloads where the operator is willing to read the source. It is not a drop-in replacement for VMware vSphere or Proxmox VE for large enterprises.

---

## What's New in v2.7.2

**Security (SEC-029..033):**
- Safe archive extraction via `security_utils.safe_tar_extract`/`safe_zip_extract` — rejects path traversal, symlink escape, device-file members (B202).
- DNS rebinding mitigation: `resolve_safe_host()` resolves once, returns IP literal for direct connect.
- FTP backup deprecated behind `OXWARE_ENABLE_INSECURE_FTP=1` (B321/B402).
- SSH known-hosts replaces `paramiko.AutoAddPolicy`; pending fingerprint approvals queued for panel review (B507).
- `make security` runs Bandit + pip-audit; CI publishes SBOM artifact.

**New feature modules (~25 new REST endpoints):**
- **Kubernetes CSI driver** — expose OXware storage pools as PersistentVolumes.
- **KubeVirt bridge** — serve as the underlying hypervisor for KubeVirt CRs.
- **GitOps manager** — ArgoCD/Flux-style VM manifest sync.
- **Firecracker microVM runtime** — second-tier VM type with <125 ms boot.
- **OAuth2 provider presets** — Keycloak, Authentik, Okta, Entra, Google, GitLab.
- **Audit-log retention policy** — age + size cap, JSONL trim pass.
- **CycloneDX SBOM generator** — per-release Software Bill of Materials.
- **PWA offline mode** — service worker + read-only fallback view.

**i18n parity:**
- 6th interface language added: French (FR), full parity (2214 entries).
- CI workflow blocks merges that introduce untranslated Turkish strings.
- `make i18n` + pre-commit hook auto-refresh `PAGE_STRINGS` whenever `index.html` changes.

---

## Status & Honest Assessment

- **Maturity**: ~6 months of active development. Single primary maintainer.
- **Tested on**: Ubuntu 22.04, Debian 12. Other distributions are not supported.
- **Production readiness**: Tested by a small number of operators (~10s of nodes). Not battle-tested at fleet scale.
- **What works well**: VM lifecycle (create/start/stop/snapshot/clone), libvirt network management, noVNC console, nftables firewall, OVA/QCOW2 import, scheduled backups, RBAC, LDAP/AD, SAML/OIDC SSO, 2FA.
- **What is experimental**: clustering (DRS, fault tolerance, storage DRS), Kubernetes CSI/Operator, Firecracker microVM, WASM runtime, edge mode. These features ship behind feature flags and should not be relied on for production yet.
- **Known gaps**: no formal threat model published; limited automated test coverage; no third-party security audit yet.

If you need a production hypervisor with vendor support today, use Proxmox VE, XCP-ng, or Nutanix. If you want to run your own software-defined hypervisor and are comfortable with the trade-offs, read on.

---

## Quick Install

```bash
curl -sSL https://oxware.top/install.sh | sudo bash
```

This bootstrap clones the repository to `/opt/oxware-src` and runs the real installer (`install.sh`).

**Manual install** (if you prefer not to pipe curl into bash):

```bash
git clone https://github.com/ShinnAsukha/oxware-hypervisor.git /opt/oxware-src
cd /opt/oxware-src
sudo bash install.sh
```

After installation, the web UI is available at `https://<host-ip>:8006`. The first visit walks you through admin user creation.

**Requirements**: Ubuntu 22.04+ or Debian 12+, x86_64, 4 GB RAM minimum (16 GB recommended), KVM-capable CPU (Intel VT-x / AMD-V).

---

## Features

### Core
- VM lifecycle: create, start, stop, pause, snapshot, clone, delete, force-kill
- Disk management: qcow2, live disk hot-extend, SMART monitoring
- Console: noVNC (browser), SPICE, xterm.js serial via virsh
- Import: OVA, OVF, VMDK, VHD, VHDX, raw, qcow2
- Live migration between two OXware nodes (same-CPU only without EVC)
- Cloud-init for first-boot configuration (static IP, SSH key, hostname)

### Networking
- libvirt networks: NAT, bridge, isolated, routed
- IPAM with CIDR pools, DHCP static leases, subnet calculator
- Per-VM nftables firewall
- Port forwarding (DNAT rules with persistence)
- HAProxy and WireGuard helpers
- BGP peering (FRR-based)

### Storage
- Storage pools: directory, LVM, NFS
- Snapshots: live, scheduled, app-consistent (via guest agent fsfreeze)
- Backups: local, MinIO/S3, SFTP, 3-2-1 automation, mount + boot verification
- Cross-site disk replication (rsync or qemu-img+ssh)

### Access Control
- Four roles: `administrator`, `operator`, `viewer`, `vm-user`
- TOTP 2FA with single-use recovery codes
- SAML 2.0 and OpenID Connect SSO (Okta, Azure AD, Google Workspace, Keycloak)
- LDAP/AD with group-to-role mapping
- API key tokens with permission scopes
- Session management and revocation
- Per-IP rate limiting on auth endpoints
- Hash-chained audit log

### Enterprise Features (status varies — see [`feature_registry.py`](oxware/backend/feature_registry.py))
- Cluster: DRS auto-balancing, EVC CPU baseline, affinity rules, maintenance mode
- DR: site recovery runbooks, cross-site replication, RPO/RTO tracking, fault tolerance (checkpoint-based)
- Multi-tenancy: hard isolation, per-tenant quotas, chargeback engine, service catalog
- Security: vTPM 2.0, UEFI Secure Boot, LUKS2 live disk encryption, AMD SEV/Intel TDX (where hardware supports)
- Compliance: automated scanning against CIS Ubuntu, NIST 800-53, PCI-DSS, HIPAA, ISO 27001
- Observability: OpenTelemetry tracing, Grafana panel embedding, topology graph, capacity forecasting
- Power: Green Mode with AI-driven cluster consolidation, idle node suspension (ACPI/IPMI/WoL)

Each enterprise feature can be enabled or disabled via the feature registry. Some features require specific kernel modules, external services, or hardware support — the registry tracks dependencies and current status.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Web UI (HTML/JS, no build step)        REST API + WebSocket │
│         ↕                                       ↕            │
│                    Flask 3.x backend                          │
│         ↕                                       ↕            │
│   libvirt / QEMU              nftables / iptables             │
│         ↕                                                     │
│   KVM (Linux kernel)                                          │
└─────────────────────────────────────────────────────────────┘
```

**Components**:
- Backend: Python 3.10+, Flask, Flask-SocketIO, libvirt-python
- Frontend: Single-page HTML with vanilla JS (no React/Vue/Webpack)
- Reverse proxy: nginx with Let's Encrypt
- Process supervision: systemd
- Storage: qcow2 on local disk, optionally backed by LVM, ZFS, Ceph, or NFS
- Networking: libvirt-managed bridges, nftables for firewall, optional Open vSwitch

The backend is a single Flask process. All long-running background work is request-triggered — there are no periodic cron-like loops inside the application (this is a deliberate design choice to keep idle CPU at zero). Scheduled tasks (backups, snapshots) are managed via systemd timers.

---

## API

The REST API is documented and explorable at `https://<host>:8006/api/docs` (Swagger UI, auto-generated from Flask routes). All endpoints use JWT bearer tokens or session cookies.

Authentication:

```bash
# Get a token
curl -k -X POST https://host:8006/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"yourpass"}'

# Use it
curl -k https://host:8006/api/vms -H "Authorization: Bearer $TOKEN"
```

The full OpenAPI 3 spec is exposed at `/api/openapi`. Roughly 230 endpoints across VM management, networking, storage, RBAC, monitoring, and the enterprise modules.

A Terraform provider is available at [`terraform-provider-oxware/`](terraform-provider-oxware/) with resources for `oxware_vm`, `oxware_network`, and `oxware_storage_pool`.

---

## Configuration

Main config: `/etc/oxware/oxware.conf` (INI format). Key sections:

```ini
[server]
host = 0.0.0.0
port = 8006
secret_key = <auto-generated on first install>

[storage]
data_dir = /var/lib/oxware
iso_dir = /var/lib/oxware/isos

[libvirt]
uri = qemu:///system
```

Per-user state (preferences, API keys) is stored under `/var/lib/oxware/`. Logs go to `/var/log/oxware/`.

---

## Security

If you find a security issue, please email the maintainer rather than opening a public GitHub issue. Disclosure policy is in [SECURITY.md](SECURITY.md).

Hardening notes for production:
- Put the web UI behind a reverse proxy with a proper TLS certificate (Let's Encrypt helper is included).
- Restrict access with an IP allowlist (`/api/settings/ip-allowlist`).
- Enable 2FA for all admin and operator accounts.
- Generate 2FA recovery codes and store them offline.
- Use SSO (SAML/OIDC) if you have an existing identity provider.
- Review the audit log regularly (`/api/audit/logs` or `journalctl -u oxware`).
- For kernel-level hardening (AppArmor profile, seccomp filter, eBPF/XDP), see [`kernel/install-hardening.sh`](kernel/install-hardening.sh).

The kernel hardening installer is opt-in and ships with rollback. If the service fails to start after applying hardening, run:

```bash
sudo bash repair.sh --remove-hardening
```

---

## Repair & Diagnostics

`repair.sh` is the recovery tool. It handles most common failure modes:

```bash
sudo bash repair.sh --diagnose            # read-only health check
sudo bash repair.sh                       # full repair
sudo bash repair.sh --remove-hardening    # rollback kernel hardening
sudo bash repair.sh --fix-apparmor        # disable broken AppArmor profile
sudo bash repair.sh --clean-disk          # truncate logs, vacuum journal
sudo bash repair.sh --restore-network     # restore netplan from backup
sudo bash repair.sh --reset-credentials   # reset admin password
```

If `repair.sh --diagnose` shows everything green and the service still fails, look at `journalctl -u oxware -n 100` and open a GitHub issue with the output.

---

## Comparison with Other Hypervisor Stacks

OXware is not a drop-in replacement for the platforms below. The comparison is meant to set expectations.

| Platform | Best for | OXware fit |
|---|---|---|
| **VMware vSphere** | Large enterprise, vendor support, vSAN | Not a peer. Use vSphere if you need licensed enterprise support. |
| **Proxmox VE** | Mid-size production, mature ecosystem | Proxmox is more mature. OXware is more focused on a single-binary REST API and modern enterprise integrations. |
| **XCP-ng / Xen** | Citrix-derived deployments, Xen workloads | Different hypervisor (Xen vs KVM). Choose based on hypervisor preference. |
| **OpenStack** | Multi-tenant public/private cloud | OpenStack is a much larger ops investment. OXware does not aim to compete. |
| **Harvester** | HCI on KVM | Harvester targets HCI specifically. OXware is more general-purpose. |
| **virt-manager** | Single-host desktop GUI | virt-manager is local-only. OXware adds a web UI, multi-user RBAC, and REST API. |

Use the right tool. Open issues if you find features missing that block your use case — feedback is welcome.

---

## Roadmap

The roadmap and current release notes live in [CHANGELOG.md](CHANGELOG.md) and the [releases page](https://github.com/ShinnAsukha/oxware-hypervisor/releases).

Near-term priorities (next 6–12 months):
- Stabilize the clustering features (currently beta)
- Reduce the size of the single `app.py` file by splitting into Flask blueprints
- Add a formal automated test suite (currently mostly manual testing)
- Publish a threat model and request a third-party security review
- Improve documentation for production deployments

---

## Contributing

Pull requests are welcome. Before opening a PR:
1. Run `bash repair.sh --diagnose` and confirm the system is healthy
2. Test your change locally against a fresh VM
3. Include a short note about what you tested
4. Keep commits focused and easy to review

See [CONTRIBUTING.md](CONTRIBUTING.md) for the longer version.

---

## License

MIT — see [LICENSE](LICENSE).

---

## Acknowledgements

OXware builds on top of work by the libvirt, QEMU, KVM, Flask, noVNC, and many other open source projects. Without those communities this project would not exist.
