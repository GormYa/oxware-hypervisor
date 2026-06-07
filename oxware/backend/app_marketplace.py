"""
OXware App Marketplace
Community VM templates, automation workflows, plugin registry.
Local cache: /var/lib/oxware/marketplace/
Manifest: /var/lib/oxware/marketplace/index.json
Remote: https://marketplace.oxware.top/index.json (optional, with offline fallback)
"""

import hashlib
import json
import os
import shutil
import tarfile
import time
import urllib.request
import urllib.error
from pathlib import Path

CACHE_DIR = Path("/var/lib/oxware/marketplace")
INDEX_FILE = CACHE_DIR / "index.json"
INSTALLED_FILE = CACHE_DIR / "installed.json"
APPS_DIR = CACHE_DIR / "apps"
LOG_DIR = Path("/var/log/oxware")
LOG_FILE = LOG_DIR / "marketplace.jsonl"

REMOTE_INDEX_URL = "https://marketplace.oxware.top/index.json"

BUNDLED_APPS = [
    {
        "id": "ubuntu-server-24.04",
        "name": "Ubuntu Server 24.04 LTS",
        "description": "Official Ubuntu Server 24.04 LTS cloud image template.",
        "category": "os",
        "tags": ["ubuntu", "linux", "lts", "server"],
        "vm_spec": {"vcpus": 2, "ram_mb": 2048, "disk_gb": 20},
        "url": "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img",
        "sha256": "",
        "version": "24.04.1",
    },
    {
        "id": "debian-12-cloud",
        "name": "Debian 12 Cloud",
        "description": "Debian 12 Bookworm cloud-init enabled image.",
        "category": "os",
        "tags": ["debian", "linux", "cloud-init"],
        "vm_spec": {"vcpus": 2, "ram_mb": 2048, "disk_gb": 20},
        "url": "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2",
        "sha256": "",
        "version": "12",
    },
    {
        "id": "windows-server-2022-trial",
        "name": "Windows Server 2022 (Trial)",
        "description": "Windows Server 2022 evaluation image, 180-day trial.",
        "category": "os",
        "tags": ["windows", "microsoft", "trial"],
        "vm_spec": {"vcpus": 4, "ram_mb": 8192, "disk_gb": 60},
        "url": "",
        "sha256": "",
        "version": "21H2",
    },
    {
        "id": "wordpress-lamp",
        "name": "WordPress on LAMP",
        "description": "Pre-configured WordPress on Apache + MySQL + PHP stack.",
        "category": "app",
        "tags": ["wordpress", "lamp", "blog", "cms"],
        "vm_spec": {"vcpus": 2, "ram_mb": 4096, "disk_gb": 25},
        "url": "",
        "sha256": "",
        "version": "6.5",
    },
    {
        "id": "gitlab-ce",
        "name": "GitLab CE",
        "description": "Self-hosted GitLab Community Edition for SCM/CI.",
        "category": "devops",
        "tags": ["gitlab", "git", "ci", "devops"],
        "vm_spec": {"vcpus": 4, "ram_mb": 8192, "disk_gb": 60},
        "url": "",
        "sha256": "",
        "version": "17.0",
    },
    {
        "id": "github-runner",
        "name": "GitHub Actions Runner",
        "description": "Self-hosted GitHub Actions runner template.",
        "category": "devops",
        "tags": ["github", "ci", "runner", "actions"],
        "vm_spec": {"vcpus": 2, "ram_mb": 4096, "disk_gb": 30},
        "url": "",
        "sha256": "",
        "version": "2.317.0",
    },
    {
        "id": "nginx-reverse-proxy",
        "name": "Nginx Reverse Proxy",
        "description": "Hardened Nginx reverse proxy with auto-renewing Let's Encrypt.",
        "category": "network",
        "tags": ["nginx", "proxy", "tls", "letsencrypt"],
        "vm_spec": {"vcpus": 1, "ram_mb": 1024, "disk_gb": 10},
        "url": "",
        "sha256": "",
        "version": "1.26",
    },
    {
        "id": "docker-host",
        "name": "Docker Host",
        "description": "Minimal VM with Docker Engine + Compose pre-installed.",
        "category": "container",
        "tags": ["docker", "container", "compose"],
        "vm_spec": {"vcpus": 2, "ram_mb": 4096, "disk_gb": 30},
        "url": "",
        "sha256": "",
        "version": "27.0",
    },
]


def _ensure_dirs():
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        APPS_DIR.mkdir(parents=True, exist_ok=True)
        LOG_DIR.mkdir(parents=True, exist_ok=True)
    except PermissionError:
        pass


def _audit(action: str, payload: dict) -> None:
    _ensure_dirs()
    entry = {"ts": time.time(), "action": action, **payload}
    try:
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
    except OSError:
        pass


def _load_index() -> list:
    _ensure_dirs()
    if not INDEX_FILE.exists():
        return list(BUNDLED_APPS)
    try:
        with open(INDEX_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, dict) and "apps" in data:
                return data["apps"]
            if isinstance(data, list):
                return data
    except (json.JSONDecodeError, OSError):
        pass
    return list(BUNDLED_APPS)


def _save_index(apps: list) -> None:
    _ensure_dirs()
    tmp = INDEX_FILE.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"apps": apps, "updated_at": time.time()}, f, indent=2)
    os.replace(tmp, INDEX_FILE)


def _load_installed() -> dict:
    if not INSTALLED_FILE.exists():
        return {}
    try:
        with open(INSTALLED_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {}


def _save_installed(data: dict) -> None:
    _ensure_dirs()
    tmp = INSTALLED_FILE.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, INSTALLED_FILE)


def list_apps(category=None) -> list:
    apps = _load_index()
    if category:
        return [a for a in apps if a.get("category") == category]
    return apps


def search_apps(query: str) -> list:
    q = (query or "").lower().strip()
    if not q:
        return []
    out = []
    for a in _load_index():
        hay = " ".join([
            a.get("name", ""),
            a.get("description", ""),
            " ".join(a.get("tags", [])),
            a.get("id", ""),
        ]).lower()
        if q in hay:
            out.append(a)
    return out


def get_app(app_id: str) -> dict:
    for a in _load_index():
        if a.get("id") == app_id:
            return a
    raise KeyError(f"app {app_id} not found")


def install_app(app_id: str, target_dir=None) -> dict:
    app = get_app(app_id)
    _ensure_dirs()
    dest = Path(target_dir) if target_dir else (APPS_DIR / app_id)
    dest.mkdir(parents=True, exist_ok=True)

    url = app.get("url", "")
    expected_sha = app.get("sha256", "")
    tarball_path = dest / f"{app_id}.tar.gz"
    downloaded = False
    actual_sha = ""

    if url:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "OXware/2.6.3"})
            with urllib.request.urlopen(req, timeout=30) as resp, open(tarball_path, "wb") as f:
                shutil.copyfileobj(resp, f)
            downloaded = True
            h = hashlib.sha256()
            with open(tarball_path, "rb") as f:
                for chunk in iter(lambda: f.read(65536), b""):
                    h.update(chunk)
            actual_sha = h.hexdigest()
            if expected_sha and actual_sha != expected_sha:
                tarball_path.unlink(missing_ok=True)
                raise ValueError(f"sha256 mismatch: got {actual_sha} expected {expected_sha}")
            if tarfile.is_tarfile(tarball_path):
                with tarfile.open(tarball_path, "r:*") as tf:
                    tf.extractall(dest)
        except (urllib.error.URLError, OSError, ValueError) as e:
            _audit("install_failed", {"app_id": app_id, "error": str(e)})
            if not isinstance(e, ValueError):
                downloaded = False
            else:
                raise

    installed = _load_installed()
    record = {
        "app_id": app_id,
        "name": app.get("name", app_id),
        "version": app.get("version", ""),
        "path": str(dest),
        "installed_at": time.time(),
        "sha256": actual_sha,
        "downloaded": downloaded,
    }
    installed[app_id] = record
    _save_installed(installed)
    _audit("install", {"app_id": app_id, "downloaded": downloaded})
    return record


def uninstall_app(app_id: str) -> dict:
    installed = _load_installed()
    if app_id not in installed:
        raise KeyError(f"app {app_id} not installed")
    path = Path(installed[app_id].get("path", ""))
    if path.exists() and str(path).startswith(str(APPS_DIR)):
        shutil.rmtree(path, ignore_errors=True)
    del installed[app_id]
    _save_installed(installed)
    _audit("uninstall", {"app_id": app_id})
    return {"removed": app_id, "ok": True}


def refresh_index() -> dict:
    _ensure_dirs()
    try:
        req = urllib.request.Request(REMOTE_INDEX_URL,
                                     headers={"User-Agent": "OXware/2.6.3"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        apps = data.get("apps", data) if isinstance(data, dict) else data
        if not isinstance(apps, list):
            raise ValueError("bad index format")
        _save_index(apps)
        _audit("refresh_index", {"source": "remote", "count": len(apps)})
        return {"source": "remote", "count": len(apps), "ok": True}
    except (urllib.error.URLError, OSError, ValueError, json.JSONDecodeError) as e:
        _save_index(list(BUNDLED_APPS))
        _audit("refresh_index", {"source": "bundled", "error": str(e)})
        return {"source": "bundled", "count": len(BUNDLED_APPS),
                "ok": True, "offline": True, "error": str(e)}


def submit_app(manifest: dict) -> dict:
    if not isinstance(manifest, dict) or "id" not in manifest or "name" not in manifest:
        raise ValueError("manifest requires id and name")
    submission = {
        "submitted_at": time.time(),
        "manifest": manifest,
        "status": "queued",
    }
    _audit("submit_app", {"app_id": manifest.get("id")})
    try:
        payload = json.dumps(manifest).encode("utf-8")
        req = urllib.request.Request(
            "https://marketplace.oxware.top/submit",
            data=payload,
            headers={"Content-Type": "application/json",
                     "User-Agent": "OXware/2.6.3"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            submission["remote_status"] = resp.status
    except (urllib.error.URLError, OSError) as e:
        submission["remote_status"] = "offline"
        submission["error"] = str(e)
    return submission


def get_installed() -> list:
    installed = _load_installed()
    return list(installed.values())


def get_categories() -> list:
    apps = _load_index()
    return sorted({a.get("category", "misc") for a in apps if a.get("category")})
