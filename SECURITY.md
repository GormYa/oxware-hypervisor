# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 2.5.x (latest) | ✅ Active support |
| 2.x (older)    | ⚠️  Security patches only |
| 1.x            | ❌ End of life |

## Reporting a Vulnerability

**Do NOT open a public GitHub issue for security vulnerabilities.**

Report vulnerabilities privately via one of the following:

- **Email:** adalyan06@gmail.com
- **GitHub Private Advisory:** [Security Advisories](https://github.com/ShinnAsukha/oxware-hypervisor/security/advisories/new)

### What to include

- Description of the vulnerability
- Steps to reproduce
- Affected component (backend, frontend, installer, license system)
- Potential impact assessment
- Your suggested fix (optional)

### Response timeline

| Stage | Timeframe |
|-------|-----------|
| Initial acknowledgement | Within 48 hours |
| Triage & severity assessment | Within 7 days |
| Fix development | Within 30 days (critical: 7 days) |
| Public disclosure | After fix is released |

We follow **responsible disclosure** — we will coordinate with you before any public announcement.

---

## Security Architecture

OXware runs as root on a KVM hypervisor host. The attack surface includes:

| Component | Notes |
|-----------|-------|
| Web UI (HTTPS :8006) | Flask + self-signed SSL, JWT auth |
| libvirt socket | Unix socket, root only |
| VNC ports (5900–5999) | Per-VM, bound to host |
| noVNC WebSocket (:6080) | Proxied through OXware |

### Default hardening

- UFW firewall enabled on install (SSH + 8006 + VNC only)
- fail2ban active on SSH and web UI
- SSL/TLS enforced on all web traffic
- JWT tokens HS256-only (alg:none blocked)
- All VM operations require authentication
- PBKDF2-SHA256 with 260,000 iterations for passwords
- Machine-ID based AES-256-CBC credential encryption

---

## Known Security Considerations

- **Self-signed SSL:** Browsers will show a warning. Replace with a trusted certificate for production use.
- **Root process:** OXware runs as root (required for KVM/libvirt). Restrict network access accordingly.
- **VNC ports:** VNC sessions are not encrypted by default. Use noVNC (WebSocket proxy) or a VPN.
- **SSH key-only:** Installer configures SSH with `PermitRootLogin prohibit-password`. Use SSH keys.
- **CORS:** Configure `cors_origins` in `/etc/oxware/oxware.conf` if frontend and API are on different origins.

---

## v2.5 Security Fixes — Güvenlik Güncellemesi

Aşağıdaki bulgular v2.5 sürümünde çözülmüş ve kullanıcılara açıklanmıştır.

### ✅ Kritik (Critical)

| ID | Başlık | CVSS | Durum |
|----|--------|------|-------|
| OXW-2026-014 | `/api/update/*` uçnoktalarında rol kontrolü eksikliği — herhangi bir kullanıcı supply-chain RCE yapabiliyordu | 9.9 | ✅ **Düzeltildi** — `@require_role("administrator")` eklendi |
| OXW-2026-015 | Güncelleyicide repo_url allow-list yoktu — zararlı repo URL kabul ediliyordu | 9.1 | ✅ **Düzeltildi** — `UPDATE_ALLOWED_REPOS` config ile kısıtlandı |
| OXW-2026-001 | CSRF "token yoksa geç" baypası — çift gönderim koruması işlevsizdi | 9.0 | ✅ **Düzeltildi** — Bearer header hariç tüm isteklerde token zorunlu |
| OXW-2026-002 | CORS `origins="*"` + `supports_credentials=True` — CSRF ile zincirlenince admin RCE | 8.8 | ✅ **Düzeltildi** — Config tabanlı beyaz liste; wildcard kaldırıldı |

### ✅ Yüksek (High)

| ID | Başlık | CVSS | Durum |
|----|--------|------|-------|
| OXW-2026-016 | VNC WebSocket çerçeve uzunluğu sınırsızdı — bellek bombası DoS | 7.5 | ✅ **Düzeltildi** — 16 MiB çerçeve sınırı |
| OXW-2026-005 | `/api/auth/2fa/debug` anlık TOTP kodunu döndürüyordu — 2FA bypass | 7.1 | ✅ **Düzeltildi** — Endpoint üretimden kaldırıldı (410 Gone) |
| OXW-2026-004 | XFF başlığı ile rate-limit ve lockout bypass | 7.5 | ✅ **Düzeltildi** — Yalnızca `trusted_proxies` CIDR'inden XFF kabul |
| OXW-2026-018 | LDAP arama filtresi enjeksiyonu — kullanıcı sayımı | 7.0 | ✅ **Düzeltildi** — RFC 4515 escape (`_ldap_escape`) |
| rapor #33 | SSH `PermitRootLogin yes` + `PasswordAuthentication yes` — brute-force davetiyesi | HIGH | ✅ **Düzeltildi** — `prohibit-password` + `PasswordAuthentication no` |
| rapor #6 | Update endpoint: herhangi bir kullanıcı supply-chain RCE | HIGH | ✅ **Düzeltildi** (OXW-2026-014 ile) |

### ✅ Orta (Medium)

| ID | Başlık | CVSS | Durum |
|----|--------|------|-------|
| OXW-2026-020 | `_2fa_pending` kilitsiz TOCTOU + bellek sızıntısı | 5.3 | ✅ **Düzeltildi** — `threading.Lock` + atomik pop + cleanup thread |
| OXW-2026-019 | API key ham SHA-256 + sabit-zamanlı olmayan karşılaştırma | 5.0 | ✅ **Düzeltildi** — HMAC-SHA256 (pepper) + `hmac.compare_digest` |
| OXW-2026-017 | Webhook URL SSRF — iç ağ taraması yapılabiliyordu | 6.5 | ✅ **Düzeltildi** — RFC1918/loopback/link-local block-list |
| OXW-2026-007 | `/api/pentest/run` SSRF — yönetici iç ağa yönlendirme | 6.5 | ✅ **Düzeltildi** — İç ağ block-list zorunlu |
| OXW-2026-006 | Lockout state bellekte — yeniden başlatmada sıfırlanıyordu | 5.3 | ✅ **Düzeltildi** — `lockouts.json` diske persist |
| OXW-2026-011 | DiyOcp PHP TLS doğrulama devre dışı seçeneği | 4.2 | ✅ **Düzeltildi** — `CURLOPT_SSL_VERIFYPEER` her zaman true |
| rapor #19 | Parola politikası yoktu — "123456" gibi şifreler kabul ediliyordu | MEDIUM | ✅ **Düzeltildi** — Uzunluk, karmaşıklık, yaygın şifre kontrolü |

### ✅ Düşük (Low) / Bilgi (Info)

| ID | Başlık | Durum |
|----|--------|-------|
| OXW-2026-013 | Legacy SHA256 migration flag hatası | ✅ **Düzeltildi** — `migrated = True` atama hatası giderildi |
| OXW-2026-010 | `install.sh` `set -e` devre dışıydı — sessiz kurulum hataları | ✅ **Düzeltildi** — `set -uo pipefail` aktif |
| Hardcoded IP | `pentest.py` içinde production sunucu IP'si açık kodda | ✅ **Düzeltildi** — `REDACTED_HOST` → `127.0.0.1`, git geçmişi temizlendi |

### 🔄 Devam Eden İyileştirmeler (Faz 2–4)

Aşağıdaki bulgular çözüm sürecindedir veya mimari değişiklik gerektirmektedir:

| ID | Başlık | Öncelik |
|----|--------|---------|
| OXW-2026-003 | `/api/system/execute` — kabul: zorunlu re-auth + komut whitelist | Orta vade |
| OXW-2026-008 | VNC WebSocket JWT sorgu dizesinde — tek kullanımlık token gerekli | 1 hafta |
| OXW-2026-009 | libvirt `auth_unix_rw="none"` → polkit geçişi | 1 ay |
| OXW-2026-012 | Login timing oracle — sabit-zamanlı dummy PBKDF2 yolu | 1 hafta |
| rapor #16 | Stateless JWT revocation — aktif token blocklist | 1 hafta |
| rapor #25 | VM disk/RAM quota kontrolü yok | 2 hafta |
| rapor #28 | WebSocket event wildcard (`*`) — kiracı izolasyonu | 1 hafta |

---

## Vulnerability Disclosure History

| CVE / ID | Severity | Component | Status |
|----------|----------|-----------|--------|
| OMERATI-2026-001 | **Critical** (CVSS 9.4) | VNC WebSocket middleware | ✅ Fixed in v2.2.1 |
| OMERATI-2026-002 | **Critical** (CVSS 9.8) | Password reset API | ✅ Fixed in v2.2.2 |
| OXW-2026-014 | **Critical** (CVSS 9.9) | Update endpoint auth bypass | ✅ Fixed in v2.5.0 |
| OXW-2026-001 | **Critical** (CVSS 9.0) | CSRF bypass | ✅ Fixed in v2.5.0 |
| OXW-2026-002 | **Critical** (CVSS 8.8) | CORS wildcard + credentials | ✅ Fixed in v2.5.0 |
| OXW-2026-015 | **Critical** (CVSS 9.1) | Updater signature/allowlist | ✅ Fixed in v2.5.0 |
| OXW-2026-016 | **High** (CVSS 7.5) | WebSocket memory bomb DoS | ✅ Fixed in v2.5.0 |
| OXW-2026-005 | **High** (CVSS 7.1) | 2FA debug TOTP leak | ✅ Fixed in v2.5.0 |
| OXW-2026-004 | **High** (CVSS 7.5) | XFF rate-limit bypass | ✅ Fixed in v2.5.0 |
| OXW-2026-018 | **High** (CVSS 7.0) | LDAP filter injection | ✅ Fixed in v2.5.0 |

---

## Hall of Fame

We thank the following researchers for responsible disclosures:

- **OMERATI-2026-001** — VNC WebSocket role bypass. Fixed in v2.2.1.
- **OMERATI-2026-002** — Unauthenticated password reset RCE. Fixed in v2.2.2.
- **Zencefil Efendi** — Comprehensive white-box security audit (2026-05-24). 20 findings including 4 critical attack chains. All critical and high findings addressed in v2.5.0.

---

*OXware Security Team — adalyan06@gmail.com*
