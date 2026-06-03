"""
OXware SSO Manager — SAML 2.0 + OpenID Connect
────────────────────────────────────────────────
Provider-agnostic config + redirect flow stubs.
Real cryptographic verification requires python3-saml / authlib (optional).

This module:
  - Stores IdP configuration (entity_id, metadata_url, x509 cert)
  - Provides SAML AuthnRequest + ACS endpoints (stub-validated when libs missing)
  - Provides OIDC authorize + callback endpoints
  - Maps IdP attributes (email, role) to OXware user

Config: /var/lib/oxware/sso_config.json
"""
from __future__ import annotations
import os, json, logging, secrets, base64, time
from pathlib import Path

log = logging.getLogger("sso_manager")
_CFG = Path("/var/lib/oxware/sso_config.json")


def _load() -> dict:
    try:
        if _CFG.exists():
            return json.loads(_CFG.read_text(encoding="utf-8"))
    except Exception:
        pass
    return {
        "saml": {"enabled": False, "entity_id": "", "metadata_url": "", "x509_cert": "",
                 "acs_url": "", "sso_url": "", "attr_email": "email", "attr_role": "role"},
        "oidc": {"enabled": False, "issuer": "", "client_id": "", "client_secret": "",
                 "redirect_uri": "", "scope": "openid email profile",
                 "claim_email": "email", "claim_role": "role"},
        "role_map": {"admin": "admin", "operator": "operator", "user": "vm-user"},
    }


def _save(d: dict):
    _CFG.parent.mkdir(parents=True, exist_ok=True)
    _CFG.write_text(json.dumps(d, indent=2), encoding="utf-8")
    try:
        os.chmod(_CFG, 0o600)
    except Exception:
        pass


def get_config() -> dict:
    """Return config WITHOUT secrets (for display)."""
    d = _load()
    redacted = json.loads(json.dumps(d))  # deep copy
    if redacted.get("oidc", {}).get("client_secret"):
        redacted["oidc"]["client_secret"] = "***"
    return redacted


def update_config(saml: dict = None, oidc: dict = None, role_map: dict = None) -> dict:
    d = _load()
    if saml is not None:
        d["saml"] = {**d.get("saml", {}), **saml}
    if oidc is not None:
        old_secret = d.get("oidc", {}).get("client_secret", "")
        d["oidc"] = {**d.get("oidc", {}), **oidc}
        # Don't wipe secret if frontend sent "***"
        if oidc.get("client_secret") == "***":
            d["oidc"]["client_secret"] = old_secret
    if role_map is not None:
        d["role_map"] = role_map
    _save(d)
    log.info("SSO config updated")
    return {"ok": True}


# ── SAML ──────────────────────────────────────────────────────────────────────
def saml_authn_request() -> dict:
    """Build SAML AuthnRequest URL (redirect target)."""
    cfg = _load().get("saml", {})
    if not cfg.get("enabled"):
        return {"ok": False, "error": "SAML disabled"}
    if not cfg.get("sso_url"):
        return {"ok": False, "error": "sso_url missing"}
    # Stub: real impl uses python3-saml. Here we just redirect with relay_state.
    relay = secrets.token_urlsafe(16)
    return {
        "ok": True,
        "redirect_url": cfg["sso_url"],
        "relay_state":  relay,
        "note":         "Production'da python3-saml ile imzalı request üretin.",
    }


def saml_process_acs(saml_response_b64: str, relay_state: str = "") -> dict:
    """Process SAML AssertionConsumerService callback.
    NOTE: Stub validation — production requires python3-saml signature check."""
    try:
        decoded = base64.b64decode(saml_response_b64)
    except Exception:
        return {"ok": False, "error": "invalid base64"}
    try:
        # OXW-SEC-005: XXE prevention — defusedxml when available, fallback to stdlib
        # Python's stdlib xml.etree does NOT expand external entities by default (safe for XXE),
        # but defusedxml provides additional protection (billion laughs, etc.)
        try:
            import defusedxml.ElementTree as ET  # type: ignore
        except ImportError:
            import xml.etree.ElementTree as ET
        root = ET.fromstring(decoded)
        # Naive extraction — production must verify signature first
        ns = {"saml": "urn:oasis:names:tc:SAML:2.0:assertion"}
        nameid_el = root.find(".//saml:NameID", ns)
        attrs = {}
        for av in root.findall(".//saml:AttributeStatement/saml:Attribute", ns):
            name = av.get("Name", "")
            val_el = av.find("saml:AttributeValue", ns)
            if val_el is not None:
                attrs[name] = val_el.text
        return {
            "ok": True,
            "email": attrs.get(_load()["saml"].get("attr_email", "email")) or (nameid_el.text if nameid_el is not None else ""),
            "role":  attrs.get(_load()["saml"].get("attr_role", "role"), "vm-user"),
            "warning": "Signature NOT verified — install python3-saml for production",
        }
    except Exception as e:
        return {"ok": False, "error": f"parse: {e}"}


# ── OIDC ──────────────────────────────────────────────────────────────────────
def oidc_authorize_url(state: str = "") -> dict:
    """Build OIDC /authorize URL."""
    cfg = _load().get("oidc", {})
    if not cfg.get("enabled"):
        return {"ok": False, "error": "OIDC disabled"}
    if not all([cfg.get("issuer"), cfg.get("client_id"), cfg.get("redirect_uri")]):
        return {"ok": False, "error": "OIDC config incomplete"}
    state = state or secrets.token_urlsafe(16)
    from urllib.parse import urlencode
    url = f"{cfg['issuer'].rstrip('/')}/authorize?" + urlencode({
        "response_type": "code",
        "client_id":     cfg["client_id"],
        "redirect_uri":  cfg["redirect_uri"],
        "scope":         cfg.get("scope", "openid email profile"),
        "state":         state,
    })
    return {"ok": True, "redirect_url": url, "state": state}


def oidc_exchange_code(code: str, state: str = "") -> dict:
    """Exchange auth code for tokens."""
    cfg = _load().get("oidc", {})
    if not cfg.get("enabled"):
        return {"ok": False, "error": "OIDC disabled"}
    try:
        import urllib.request, urllib.parse, ssl
        data = urllib.parse.urlencode({
            "grant_type":    "authorization_code",
            "code":          code,
            "client_id":     cfg["client_id"],
            "client_secret": cfg["client_secret"],
            "redirect_uri":  cfg["redirect_uri"],
        }).encode()
        req = urllib.request.Request(f"{cfg['issuer'].rstrip('/')}/token", data=data)
        req.add_header("Content-Type", "application/x-www-form-urlencoded")
        ctx = ssl.create_default_context()
        with urllib.request.urlopen(req, timeout=10, context=ctx) as resp:
            tok = json.loads(resp.read().decode())
        # Decode ID token payload (no signature verification — stub)
        id_tok = tok.get("id_token", "")
        if id_tok and id_tok.count(".") == 2:
            payload = id_tok.split(".")[1]
            payload += "=" * (4 - len(payload) % 4)
            claims  = json.loads(base64.urlsafe_b64decode(payload))
            return {
                "ok": True,
                "email": claims.get(cfg.get("claim_email", "email"), ""),
                "role":  claims.get(cfg.get("claim_role", "role"), "vm-user"),
                "claims": claims,
                "warning": "JWT signature NOT verified — install authlib/python-jose for production",
            }
        return {"ok": False, "error": "no id_token in response"}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def map_role(idp_role: str) -> str:
    """Map IdP role string to OXware internal role."""
    rmap = _load().get("role_map", {})
    return rmap.get(idp_role, "vm-user")


def is_sso_enabled() -> bool:
    d = _load()
    return d.get("saml", {}).get("enabled") or d.get("oidc", {}).get("enabled")
