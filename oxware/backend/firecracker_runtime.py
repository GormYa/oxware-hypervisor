"""OXware Firecracker microVM runtime (v3.0).

A second-tier runtime alongside QEMU/KVM. Firecracker starts in ~125ms
and uses ~5MB RAM overhead, ideal for serverless / per-request VM
workloads. This module exposes microVM lifecycle through the same VM
API surface so panel code can treat them as just another VM type.

State: /var/lib/oxware/firecracker_vms.json
"""
from __future__ import annotations
import json
import logging
import os
import threading
import time
import uuid
from pathlib import Path

log = logging.getLogger("oxware.firecracker")
_CATALOG = Path("/var/lib/oxware/firecracker_vms.json")
_SOCKETS_DIR = Path("/run/oxware/firecracker")
_LOCK = threading.Lock()


def _load() -> dict:
    if not _CATALOG.exists():
        return {"vms": []}
    try:
        return json.loads(_CATALOG.read_text(encoding="utf-8"))
    except Exception:
        return {"vms": []}


def _save(d: dict) -> None:
    _CATALOG.parent.mkdir(parents=True, exist_ok=True)
    tmp = _CATALOG.with_suffix(".tmp")
    tmp.write_text(json.dumps(d, indent=2), encoding="utf-8")
    os.replace(tmp, _CATALOG)


def list_microvms() -> list:
    return _load().get("vms", [])


def launch(name: str, kernel_path: str, rootfs_path: str,
           vcpus: int = 1, memory_mb: int = 128) -> dict:
    """Register a Firecracker microVM. The actual jailer + firecracker
    process is started by the OXware microvm-runner systemd unit."""
    if vcpus < 1 or vcpus > 16:
        return {"ok": False, "error": "vcpus must be 1..16"}
    if memory_mb < 64 or memory_mb > 16384:
        return {"ok": False, "error": "memory_mb must be 64..16384"}
    vm = {
        "id": f"fc-{uuid.uuid4().hex[:8]}",
        "name": name,
        "kernel_path": kernel_path,
        "rootfs_path": rootfs_path,
        "vcpus": vcpus,
        "memory_mb": memory_mb,
        "api_socket": str(_SOCKETS_DIR / f"{name}.sock"),
        "state": "pending",
        "created_at": time.time(),
    }
    with _LOCK:
        d = _load()
        d["vms"].append(vm)
        _save(d)
    log.info("firecracker microVM queued: %s (%d vcpus, %dMB)",
             name, vcpus, memory_mb)
    return {"ok": True, "vm": vm}


def stop(vm_id: str) -> dict:
    with _LOCK:
        d = _load()
        for vm in d["vms"]:
            if vm["id"] == vm_id:
                vm["state"] = "stopped"
                _save(d)
                return {"ok": True, "vm_id": vm_id, "state": "stopped"}
    return {"ok": False, "error": "not found"}


def delete(vm_id: str) -> dict:
    with _LOCK:
        d = _load()
        new = [v for v in d["vms"] if v["id"] != vm_id]
        if len(new) == len(d["vms"]):
            return {"ok": False, "error": "not found"}
        d["vms"] = new
        _save(d)
    return {"ok": True, "vm_id": vm_id}
