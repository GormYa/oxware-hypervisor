"""
OXware Shared Security Validators (v2.7.1 SEC-017..023)
─────────────────────────────────────────────────────────
Reusable helpers shared by federation, runbook executor, blueprints.

- validate_external_url(): scheme+host allowlist, SSRF guard
- validate_vm_id():       canonical libvirt domain name pattern
- validate_forward_path(): allowed forward paths for federation proxy
- safe_subprocess_arg(): deny shell metacharacters in argv

Used to plug:
  SEC-017  Runbook api_call SSRF (CRITICAL)
  SEC-018  Runbook vm_action argv injection (CRITICAL)
  SEC-019  Federation member URL SSRF (HIGH)
  SEC-020  Federation forward path allowlist (MEDIUM)
  SEC-021  Federation add_member URL validation (MEDIUM)
"""
from __future__ import annotations
import ipaddress
import re
from urllib.parse import urlparse

# Strict libvirt domain name pattern — letters, digits, dot, dash, underscore.
# Excludes whitespace, semicolons, pipes, ampersands, quotes, dollar signs,
# backticks, backslashes — anything a shell would interpret.
_VM_ID_RE = re.compile(r"^[A-Za-z0-9._\-]{1,128}$")

# Allowed paths for federation forward(). Member RBAC + audit log enforce
# the action. Auth/setup/internal admin paths are denied.
_FORWARD_PATH_PREFIXES = (
    "/api/vms",
    "/api/hosts",
    "/api/alerts",
    "/api/networks",
    "/api/storage",
    "/api/monitoring",
    "/api/health",
)

# Private / loopback / link-local / reserved CIDR blocks blocked for external
# fetch unless explicit allow_loopback=True is passed.
_PRIVATE_NETS_V4 = [
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("169.254.0.0/16"),   # link-local + cloud metadata
    ipaddress.ip_network("0.0.0.0/8"),
    ipaddress.ip_network("100.64.0.0/10"),    # CGNAT
]
_PRIVATE_NETS_V6 = [
    ipaddress.ip_network("::1/128"),
    ipaddress.ip_network("fc00::/7"),         # ULA
    ipaddress.ip_network("fe80::/10"),        # link-local
    ipaddress.ip_network("fd00:ec2::/32"),    # IPv6 cloud metadata
]


class SecurityValidationError(ValueError):
    """Raised when a request is rejected by security_utils."""


def validate_vm_id(vm_id: str) -> str:
    """Return the vm_id if it matches the strict pattern, else raise."""
    if not isinstance(vm_id, str) or not _VM_ID_RE.match(vm_id):
        raise SecurityValidationError(
            "invalid vm_id: must match ^[A-Za-z0-9._-]{1,128}$"
        )
    return vm_id


def _ip_is_private(ip_str: str) -> bool:
    try:
        ip = ipaddress.ip_address(ip_str)
    except ValueError:
        return False
    if isinstance(ip, ipaddress.IPv4Address):
        for net in _PRIVATE_NETS_V4:
            if ip in net:
                return True
    else:
        for net in _PRIVATE_NETS_V6:
            if ip in net:
                return True
    return False


def validate_external_url(url: str, *, allow_loopback: bool = False,
                          allow_http: bool = False) -> str:
    """Validate URL for outbound federation/runbook api_call.

    - scheme must be https (or http if allow_http=True)
    - host must be present
    - host (if literal IP) must not be a private / loopback / link-local /
      metadata address unless allow_loopback=True

    Returns the normalized URL or raises SecurityValidationError.
    """
    if not isinstance(url, str) or not url.strip():
        raise SecurityValidationError("url must be a non-empty string")
    parsed = urlparse(url.strip())
    if parsed.scheme not in ("https", "http"):
        raise SecurityValidationError(
            f"url scheme must be https (got '{parsed.scheme}')"
        )
    if parsed.scheme == "http" and not allow_http:
        raise SecurityValidationError(
            "http:// not permitted for external calls — use https://"
        )
    if not parsed.hostname:
        raise SecurityValidationError("url has no hostname")
    host = parsed.hostname
    try:
        ipaddress.ip_address(host)
        is_ip = True
    except ValueError:
        is_ip = False
    if is_ip and not allow_loopback and _ip_is_private(host):
        raise SecurityValidationError(
            f"refusing to call private/loopback/link-local address: {host}"
        )
    if not allow_loopback and host.lower() in ("localhost", "localhost.localdomain"):
        raise SecurityValidationError(
            f"refusing to call loopback hostname: {host}"
        )
    return parsed.geturl()


def validate_forward_path(path: str) -> str:
    """Return path if it's on the federation forward allowlist, else raise."""
    if not isinstance(path, str) or not path.startswith("/"):
        raise SecurityValidationError("forward path must start with '/'")
    blocked = ("/api/auth", "/api/setup", "/api/internal", "/api/admin",
               "/api/users", "/api/sessions", "/api/.well-known")
    for b in blocked:
        if path.startswith(b):
            raise SecurityValidationError(f"forward path '{b}*' is blocked")
    for prefix in _FORWARD_PATH_PREFIXES:
        if path == prefix or path.startswith(prefix + "/") or path.startswith(prefix + "?"):
            return path
    raise SecurityValidationError(
        f"forward path '{path}' not in allowlist {_FORWARD_PATH_PREFIXES}"
    )


# Shell metacharacters that should never appear in subprocess argv elements
# derived from user input — even when the caller uses argv form, presence of
# these characters in a single element is a strong injection signal.
_SHELL_META = set(";|&`$<>\n\r\t\\\"'\x00")


def safe_subprocess_arg(value: str) -> str:
    """Return value if it contains no shell metacharacters, else raise."""
    if not isinstance(value, str):
        raise SecurityValidationError("subprocess argument must be a string")
    for ch in value:
        if ch in _SHELL_META:
            raise SecurityValidationError(
                f"subprocess argument contains shell metacharacter: {ch!r}"
            )
    return value
