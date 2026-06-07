# Security Policy

This document describes how to report a security vulnerability in OXware and
what to expect after you report it.

---

## Supported Versions

Only the latest minor release receives security patches.

| Version | Status                  |
|---------|-------------------------|
| 2.6.x   | Supported               |
| 2.5.x   | End of life 2026-09-01  |
| 2.4.x   | End of life             |
| older   | End of life             |

If you are running an unsupported version, upgrade before reporting an issue.
We will not produce patches for end-of-life branches.

---

## Reporting a Vulnerability

Do not open a public GitHub issue for a security vulnerability.

Send a report to `security@oxware.top`.

If you prefer encrypted email, use our PGP key. The current fingerprint is:

```
PGP fingerprint: TBD (will be published before 2.6.4)
```

Include in your report:

- A description of the vulnerability.
- A minimal proof of concept, if you have one.
- The affected version (`oxware --version`).
- Your name or handle if you would like to be credited.

You may also submit privately through GitHub Security Advisories:
https://github.com/ShinnAsukha/oxware-hypervisor/security/advisories/new

---

## Response Timeline

- Acknowledgement within 72 hours of receipt.
- Initial triage and severity assessment within 7 days.
- Patch for critical issues within 14 days.
- Patch for high-severity issues within 30 days.
- Patch for medium and low severity within 90 days.

These are targets, not guarantees. We will keep you informed if a fix takes
longer.

---

## Disclosure Policy

We follow coordinated disclosure with a 90-day deadline.

- We will work with you on a fix and a disclosure date.
- If we are unable to release a fix within 90 days, you may publish your
  findings. We ask that you tell us first.
- After a fix is released we publish a GitHub Security Advisory and note the
  issue in `CHANGELOG.md`.

---

## Hall of Fame

We credit researchers who report vulnerabilities responsibly.

| Researcher | Issue | Year |
|------------|-------|------|
| _(placeholder)_ | _(placeholder)_ | _(placeholder)_ |

If you want to be listed, say so in your report.

---

## Past Advisories

Published advisories are listed at:
https://github.com/ShinnAsukha/oxware-hypervisor/security/advisories

### Security Patch Summary

The following patches were issued in the 2.6.1 release:

- SEC-001: API keys are read from `/etc/oxware/oxware.conf` (mode 0600)
  instead of process environment variables.
- SEC-002: WebSocket authentication tokens are no longer passed in the URL
  query string; they are sent in the first frame after connect.
- SEC-003: JWT revocation list is consulted on every request, not only at
  refresh time.
- SEC-004: Audit log entries are hash-chained with SHA-256 so deletion or
  reordering is detectable.
- SEC-005: Login timing is equalized between unknown user and incorrect
  password to prevent user enumeration.
- SEC-006: Console session recordings are stored in a directory with mode
  0700, owned by the `oxware` user.
- SEC-007: Storage endpoints resolve paths with `os.path.realpath` and
  reject any path outside the configured root.
- SEC-008: All state-changing endpoints require a double-submit CSRF token.

---

## Hardening Recommendations

See the "Security" section of the `README.md` for the recommended
configuration of nginx, sudo, file permissions, and operating system
hardening.

---

## Out of Scope

The following findings are not eligible for a security advisory:

- Denial of service against publicly available test instances.
- Missing security headers on `/docs` (Swagger UI) when the docs endpoint
  is enabled.
- Self-XSS that requires a user to paste content into their own browser
  console.
- Missing best-practice cookie flags on a development server running in
  debug mode.
- Reports generated solely by automated scanners without a working proof
  of concept.
- Issues in dependencies for which an upstream advisory already exists.

---

## Bounty Program

OXware does not currently offer a paid bug bounty.

If a bounty program is established in a future release, it will be announced
on the project website and linked from this document.

---

## Contact

- Security email: `security@oxware.top`
- General contact: `hello@oxware.top`
- GitHub: https://github.com/ShinnAsukha/oxware-hypervisor
