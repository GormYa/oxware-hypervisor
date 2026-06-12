"""OXware CSI Driver Control Plane (v2.9).

Exposes OXware storage pools as Kubernetes PersistentVolumes via a
CSI-compatible bridge running on each k8s node. This module is the
control plane: it tracks provisioning requests, snapshots, and
resize jobs that the in-cluster CSI sidecar then executes.

State: /var/lib/oxware/csi_volumes.json
"""
from __future__ import annotations
import json
import logging
import os
import threading
import time
import uuid
from pathlib import Path

log = logging.getLogger("oxware.csi")
_CATALOG = Path("/var/lib/oxware/csi_volumes.json")
_LOCK = threading.Lock()
CSI_DRIVER_NAME = "csi.oxware.top"


def _load() -> dict:
    if not _CATALOG.exists():
        return {"volumes": []}
    try:
        return json.loads(_CATALOG.read_text(encoding="utf-8"))
    except Exception:
        return {"volumes": []}


def _save(d: dict) -> None:
    _CATALOG.parent.mkdir(parents=True, exist_ok=True)
    tmp = _CATALOG.with_suffix(".tmp")
    tmp.write_text(json.dumps(d, indent=2), encoding="utf-8")
    os.replace(tmp, _CATALOG)


def list_volumes() -> list:
    return _load().get("volumes", [])


def provision(pool: str, size_gb: int, k8s_namespace: str,
              pvc_name: str, fs_type: str = "ext4") -> dict:
    if size_gb < 1:
        return {"ok": False, "error": "size_gb must be >= 1"}
    if fs_type not in ("ext4", "xfs", "btrfs"):
        return {"ok": False, "error": f"unsupported fs_type: {fs_type}"}
    vol = {
        "id": f"pvc-{uuid.uuid4()}",
        "pool": pool,
        "size_gb": int(size_gb),
        "k8s_namespace": k8s_namespace,
        "pvc_name": pvc_name,
        "fs_type": fs_type,
        "state": "pending",
        "created_at": time.time(),
    }
    with _LOCK:
        d = _load()
        d["volumes"].append(vol)
        _save(d)
    log.info("CSI provision queued: %s (%dGB, %s)", vol["id"], size_gb, pool)
    return {"ok": True, "volume": vol}


def delete(volume_id: str) -> dict:
    with _LOCK:
        d = _load()
        new = [v for v in d["volumes"] if v["id"] != volume_id]
        if len(new) == len(d["volumes"]):
            return {"ok": False, "error": "not found"}
        d["volumes"] = new
        _save(d)
    return {"ok": True, "volume_id": volume_id}


def resize(volume_id: str, new_size_gb: int) -> dict:
    with _LOCK:
        d = _load()
        for v in d["volumes"]:
            if v["id"] == volume_id:
                if new_size_gb <= v["size_gb"]:
                    return {"ok": False, "error": "online shrink not supported"}
                v["size_gb"] = new_size_gb
                v["state"] = "resizing"
                _save(d)
                return {"ok": True, "volume": v}
    return {"ok": False, "error": "not found"}


def driver_info() -> dict:
    return {
        "name": CSI_DRIVER_NAME,
        "spec_version": "1.8.0",
        "capabilities": [
            "CREATE_DELETE_VOLUME",
            "CREATE_DELETE_SNAPSHOT",
            "EXPAND_VOLUME",
            "PUBLISH_UNPUBLISH_VOLUME",
        ],
        "supported_fs": ["ext4", "xfs", "btrfs"],
    }
