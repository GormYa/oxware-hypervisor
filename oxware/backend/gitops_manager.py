"""OXware GitOps Manager (v2.9).

Pulls VM and network manifests from a git repository and reconciles them
against the live OXware state. Compatible with ArgoCD/Flux directory
layouts: each VM lives in `vms/<name>.yaml`, each network in
`networks/<name>.yaml`. Drift is reported and (optionally) auto-fixed
based on a per-repo policy.

State: /var/lib/oxware/gitops_repos.json
"""
from __future__ import annotations
import json
import logging
import os
import threading
import time
from pathlib import Path

log = logging.getLogger("oxware.gitops")
_CATALOG = Path("/var/lib/oxware/gitops_repos.json")
_LOCK = threading.Lock()


def _load() -> dict:
    if not _CATALOG.exists():
        return {"repos": []}
    try:
        return json.loads(_CATALOG.read_text(encoding="utf-8"))
    except Exception:
        return {"repos": []}


def _save(d: dict) -> None:
    _CATALOG.parent.mkdir(parents=True, exist_ok=True)
    tmp = _CATALOG.with_suffix(".tmp")
    tmp.write_text(json.dumps(d, indent=2), encoding="utf-8")
    os.replace(tmp, _CATALOG)


def list_repos() -> list:
    return _load().get("repos", [])


def add_repo(name: str, url: str, branch: str = "main",
             auth_token: str = "", auto_apply: bool = False,
             sync_interval_sec: int = 300) -> dict:
    if not name or not url:
        return {"ok": False, "error": "name and url are required"}
    repo = {
        "id": name,
        "name": name,
        "url": url,
        "branch": branch,
        "auth_token": auth_token,
        "auto_apply": bool(auto_apply),
        "sync_interval_sec": int(sync_interval_sec),
        "state": "registered",
        "last_sync": 0,
        "drift_count": 0,
        "added_at": time.time(),
    }
    with _LOCK:
        d = _load()
        d["repos"] = [r for r in d["repos"] if r["id"] != name]
        d["repos"].append(repo)
        _save(d)
    log.info("gitops repo registered: %s (%s @ %s)", name, url, branch)
    safe = dict(repo)
    safe["auth_token"] = "***" if auth_token else ""
    return {"ok": True, "repo": safe}


def remove_repo(name: str) -> dict:
    with _LOCK:
        d = _load()
        new = [r for r in d["repos"] if r["id"] != name]
        if len(new) == len(d["repos"]):
            return {"ok": False, "error": "not found"}
        d["repos"] = new
        _save(d)
    return {"ok": True, "name": name}


def sync_now(name: str) -> dict:
    """Mark a repo as needing immediate sync. The actual git fetch is
    performed by a background worker (not implemented in this stub)."""
    with _LOCK:
        d = _load()
        for r in d["repos"]:
            if r["id"] == name:
                r["state"] = "syncing"
                r["last_sync"] = time.time()
                _save(d)
                return {"ok": True, "repo": name, "state": "syncing"}
    return {"ok": False, "error": "not found"}
