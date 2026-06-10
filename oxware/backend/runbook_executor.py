"""
OXware Runbook Executor — auto-remediation engine.
───────────────────────────────────────────────────
Pre-approved runbooks fire when the anomaly detector raises a high-confidence
event. Each runbook has:
  - id, name, description
  - trigger: metric pattern + z-score threshold + cooldown
  - steps: ordered list of actions (api_call | shell | notify | vm_action)
  - approval: "auto" | "manual"  (only "auto" runs unattended)
  - max_runs_per_hour: safety cap

State:
  /var/lib/oxware/runbooks.json        catalog
  /var/lib/oxware/runbook_history.jsonl audit (append-only)

Integration: anomaly_detector.run_detection() may call
    runbook_executor.on_anomaly(anomaly_record)
which selects matching runbooks and executes them.
"""
from __future__ import annotations
import json
import logging
import os
import subprocess
import threading
import time
import urllib.request
from pathlib import Path

log = logging.getLogger("oxware.runbook")

_CATALOG = Path("/var/lib/oxware/runbooks.json")
_HISTORY = Path("/var/lib/oxware/runbook_history.jsonl")
_LOCK = threading.Lock()
_LAST_RUN: dict = {}  # runbook_id -> [timestamps]

DEFAULT_RUNBOOKS = [
    {
        "id": "rb-high-cpu-throttle",
        "name": "High CPU — throttle hot VMs",
        "description": "When host CPU sustains anomalous load, cap top consumer VMs to 60% via cgroups.",
        "trigger": {"metric_regex": r"^system\.cpu$", "min_z": 3.0, "cooldown_sec": 600},
        "steps": [
            {"type": "notify", "level": "WARNING",
             "message": "Auto-throttle triggered by anomaly"},
            {"type": "api_call", "method": "POST",
             "url": "http://127.0.0.1:8080/api/internal/throttle_top_vms",
             "json": {"cap_percent": 60, "duration_sec": 900}},
        ],
        "approval": "auto",
        "max_runs_per_hour": 4,
        "enabled": True,
    },
    {
        "id": "rb-mem-pressure-balloon",
        "name": "Memory pressure — balloon idle VMs",
        "description": "If host memory > 90% sustained anomalous, inflate balloon driver on idle VMs.",
        "trigger": {"metric_regex": r"^system\.mem$", "min_z": 3.0, "cooldown_sec": 600},
        "steps": [
            {"type": "notify", "level": "WARNING",
             "message": "Memory pressure — ballooning idle VMs"},
            {"type": "api_call", "method": "POST",
             "url": "http://127.0.0.1:8080/api/internal/balloon_idle_vms",
             "json": {"reclaim_mb": 1024}},
        ],
        "approval": "auto",
        "max_runs_per_hour": 4,
        "enabled": True,
    },
    {
        "id": "rb-disk-iops-spike",
        "name": "Disk IOPS spike — quiesce non-critical I/O",
        "description": "On per-VM IOPS anomaly, set blkio weight to lowest for tagged 'batch' VMs.",
        "trigger": {"metric_regex": r"^vm\..+\.iops$", "min_z": 3.5, "cooldown_sec": 300},
        "steps": [
            {"type": "api_call", "method": "POST",
             "url": "http://127.0.0.1:8080/api/internal/throttle_batch_io",
             "json": {"weight": 100}},
        ],
        "approval": "auto",
        "max_runs_per_hour": 6,
        "enabled": True,
    },
    {
        "id": "rb-vm-down-restart",
        "name": "VM unexpectedly stopped — auto-restart",
        "description": "If a VM with auto_restart=true stops outside a scheduled window, restart it.",
        "trigger": {"metric_regex": r"^vm\..+\.state_unexpected_stop$", "min_z": 0.0,
                    "cooldown_sec": 120},
        "steps": [
            {"type": "vm_action", "action": "start", "extract_vm_id_from": "metric_key"},
        ],
        "approval": "auto",
        "max_runs_per_hour": 3,
        "enabled": True,
    },
]


def _ensure():
    try:
        _CATALOG.parent.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass


def _load() -> list:
    _ensure()
    if not _CATALOG.exists():
        return list(DEFAULT_RUNBOOKS)
    try:
        return json.loads(_CATALOG.read_text(encoding="utf-8"))
    except Exception:
        return list(DEFAULT_RUNBOOKS)


def _save(items: list):
    _ensure()
    tmp = _CATALOG.with_suffix(".tmp")
    tmp.write_text(json.dumps(items, indent=2), encoding="utf-8")
    os.replace(tmp, _CATALOG)


def _audit(entry: dict):
    _ensure()
    entry["ts"] = time.time()
    try:
        with open(_HISTORY, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception as e:
        log.debug("history write failed: %s", e)


def list_runbooks() -> list:
    return _load()


def get_runbook(rb_id: str) -> dict | None:
    for rb in _load():
        if rb.get("id") == rb_id:
            return rb
    return None


def upsert_runbook(rb: dict) -> dict:
    if "id" not in rb:
        raise ValueError("runbook requires id")
    items = _load()
    for i, existing in enumerate(items):
        if existing.get("id") == rb["id"]:
            items[i] = rb
            break
    else:
        items.append(rb)
    _save(items)
    return rb


def delete_runbook(rb_id: str) -> bool:
    items = _load()
    new = [r for r in items if r.get("id") != rb_id]
    if len(new) == len(items):
        return False
    _save(new)
    return True


def _within_quota(rb_id: str, max_per_hour: int) -> bool:
    now = time.time()
    with _LOCK:
        hist = _LAST_RUN.get(rb_id, [])
        hist = [t for t in hist if now - t < 3600]
        if len(hist) >= max_per_hour:
            _LAST_RUN[rb_id] = hist
            return False
        hist.append(now)
        _LAST_RUN[rb_id] = hist
        return True


def _within_cooldown(rb_id: str, cooldown_sec: int) -> bool:
    now = time.time()
    hist = _LAST_RUN.get(rb_id, [])
    return hist and (now - hist[-1] < cooldown_sec)


def _run_step(step: dict, ctx: dict) -> dict:
    t = step.get("type")
    if t == "notify":
        try:
            import notifications as _notif
            _notif.send_alert(
                message=step.get("message", "runbook notification"),
                level=step.get("level", "INFO"),
                category="runbook",
                details=ctx,
            )
            return {"ok": True, "type": t}
        except Exception as e:
            return {"ok": False, "type": t, "error": str(e)}
    if t == "shell":
        cmd = step.get("cmd")
        if not isinstance(cmd, list):
            return {"ok": False, "type": t, "error": "cmd must be a list"}
        try:
            r = subprocess.run(cmd, capture_output=True, text=True,
                               timeout=step.get("timeout", 30))
            return {"ok": r.returncode == 0, "type": t,
                    "rc": r.returncode, "stdout": r.stdout[-2000:],
                    "stderr": r.stderr[-2000:]}
        except Exception as e:
            return {"ok": False, "type": t, "error": str(e)}
    if t == "api_call":
        try:
            data = None
            headers = {"Content-Type": "application/json"}
            if step.get("json") is not None:
                data = json.dumps(step["json"]).encode("utf-8")
            req = urllib.request.Request(
                step["url"], data=data, method=step.get("method", "GET"),
                headers=headers,
            )
            with urllib.request.urlopen(req, timeout=step.get("timeout", 15)) as resp:
                body = resp.read().decode("utf-8", "replace")[:4000]
                return {"ok": 200 <= resp.status < 300, "type": t,
                        "status": resp.status, "body": body}
        except Exception as e:
            return {"ok": False, "type": t, "error": str(e)}
    if t == "vm_action":
        vm_id = ctx.get("vm_id")
        if not vm_id and step.get("extract_vm_id_from") == "metric_key":
            mk = ctx.get("metric_key", "")
            # vm.<id>.<...>
            parts = mk.split(".")
            if len(parts) >= 2 and parts[0] == "vm":
                vm_id = parts[1]
        action = step.get("action", "start")
        try:
            r = subprocess.run(["virsh", action, vm_id], capture_output=True,
                               text=True, timeout=20)
            return {"ok": r.returncode == 0, "type": t, "vm_id": vm_id,
                    "action": action, "stdout": r.stdout, "stderr": r.stderr}
        except Exception as e:
            return {"ok": False, "type": t, "error": str(e)}
    return {"ok": False, "type": t, "error": "unknown step type"}


def execute_runbook(rb_id: str, ctx: dict | None = None,
                    force: bool = False) -> dict:
    rb = get_runbook(rb_id)
    if not rb:
        return {"ok": False, "error": "runbook not found"}
    if not rb.get("enabled", True) and not force:
        return {"ok": False, "error": "disabled"}
    if not force:
        cd = int(rb.get("trigger", {}).get("cooldown_sec", 0))
        if cd and _within_cooldown(rb_id, cd):
            return {"ok": False, "error": "cooldown active"}
        if not _within_quota(rb_id, int(rb.get("max_runs_per_hour", 10))):
            return {"ok": False, "error": "hourly quota exceeded"}
    ctx = ctx or {}
    results = []
    for step in rb.get("steps", []):
        results.append(_run_step(step, ctx))
    summary = {
        "ok": all(s.get("ok") for s in results),
        "runbook_id": rb_id,
        "steps": results,
        "ctx": ctx,
        "forced": force,
    }
    _audit({"event": "execute", **summary})
    return summary


def on_anomaly(anomaly: dict) -> list:
    """Called by anomaly_detector when a new anomaly is recorded.
    Returns a list of executed runbook ids."""
    import re
    out = []
    metric_key = anomaly.get("metric_key", "")
    z = float(anomaly.get("z_score", 0.0))
    for rb in _load():
        if not rb.get("enabled", True):
            continue
        if rb.get("approval", "auto") != "auto":
            continue
        trig = rb.get("trigger", {})
        pat = trig.get("metric_regex")
        if pat and not re.match(pat, metric_key):
            continue
        if z < float(trig.get("min_z", 0.0)):
            continue
        ctx = {"metric_key": metric_key, "z_score": z,
               "value": anomaly.get("current_value")}
        res = execute_runbook(rb["id"], ctx)
        if res.get("ok") or "cooldown" not in str(res.get("error", "")):
            out.append(rb["id"])
    return out


def history(limit: int = 100) -> list:
    if not _HISTORY.exists():
        return []
    try:
        with open(_HISTORY, "r", encoding="utf-8") as f:
            lines = f.readlines()[-limit:]
        return [json.loads(line) for line in lines if line.strip()]
    except Exception as e:
        log.debug("history read: %s", e)
        return []
