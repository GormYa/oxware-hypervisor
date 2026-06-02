"""
OXware CloudEvents — CloudEvents v1.0 standard format
──────────────────────────────────────────────────────
Emits events in CloudEvents v1.0 JSON (structured content mode).
Ring-buffer stores last N events in memory (no persistence flood).
Optional sink: forwards events to a configured webhook endpoint.
No external deps — stdlib + optional webhook_manager integration.
"""

import json
import time
import uuid
import logging
import threading
from pathlib import Path
from typing import Optional
from collections import deque

log = logging.getLogger("cloudevents")

_SINK_FILE     = Path("/var/lib/oxware/cloudevents_sink.json")
_lock          = threading.Lock()
_RING_SIZE     = 1000
_event_ring: deque = deque(maxlen=_RING_SIZE)

# ── Known OXware event types ──────────────────────────────────────────────────

OXWARE_EVENT_TYPES = [
    "oxware.vm.created",
    "oxware.vm.deleted",
    "oxware.vm.started",
    "oxware.vm.stopped",
    "oxware.vm.rebooted",
    "oxware.vm.suspended",
    "oxware.vm.migrated",
    "oxware.vm.error",
    "oxware.snapshot.created",
    "oxware.snapshot.deleted",
    "oxware.backup.started",
    "oxware.backup.completed",
    "oxware.backup.failed",
    "oxware.network.changed",
    "oxware.storage.threshold",
    "oxware.alert.triggered",
    "oxware.alert.resolved",
    "oxware.user.login",
    "oxware.user.logout",
    "oxware.user.failed_login",
    "oxware.policy.evaluated",
    "oxware.workflow.started",
    "oxware.workflow.completed",
    "oxware.workflow.failed",
    "oxware.maintenance.started",
    "oxware.maintenance.ended",
    "oxware.cluster.rebalanced",
    "oxware.host.degraded",
    "oxware.license.warning",
    "oxware.system.update",
]


# ── sink persistence ──────────────────────────────────────────────────────────

def _load_sink() -> dict:
    try:
        if _SINK_FILE.exists():
            return json.loads(_SINK_FILE.read_text(encoding="utf-8"))
    except Exception as e:
        log.warning("cloudevents sink load fail: %s", e)
    return {}


def _save_sink(data: dict) -> None:
    try:
        _SINK_FILE.parent.mkdir(parents=True, exist_ok=True)
        tmp = _SINK_FILE.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
        tmp.replace(_SINK_FILE)
    except Exception as e:
        log.warning("cloudevents sink save fail: %s", e)


# ── CloudEvents v1.0 envelope ─────────────────────────────────────────────────

def _build_event(event_type: str, source: str,
                 data: dict, subject: Optional[str] = None) -> dict:
    event = {
        "specversion": "1.0",
        "id":          uuid.uuid4().hex,
        "type":        event_type,
        "source":      source,
        "time":        _iso_now(),
        "datacontenttype": "application/json",
        "data":        data,
    }
    if subject:
        event["subject"] = subject
    return event


def _iso_now() -> str:
    t = time.gmtime()
    return (f"{t.tm_year:04d}-{t.tm_mon:02d}-{t.tm_mday:02d}"
            f"T{t.tm_hour:02d}:{t.tm_min:02d}:{t.tm_sec:02d}Z")


# ── sink forwarding ───────────────────────────────────────────────────────────

def _forward_to_sink(event: dict) -> None:
    """Try to forward event to configured sink. Non-fatal."""
    try:
        sink = _load_sink()
        url  = sink.get("url")
        if not url:
            return
        fmt = sink.get("format", "structured")
        try:
            import webhook_manager as _wm
            # Use webhook_manager delivery if available
            _wm.trigger(event.get("type", "cloudevent"), event)
            return
        except Exception:
            pass
        # Fallback: urllib
        import urllib.request
        import urllib.error
        body = json.dumps(event).encode()
        req  = urllib.request.Request(
            url, data=body,
            headers={"Content-Type": "application/cloudevents+json; charset=UTF-8"},
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            log.debug("cloudevent forwarded to sink: %s → %d", url, resp.status)
    except Exception as ex:
        log.debug("cloudevent sink forward fail: %s", ex)


# ── public API ────────────────────────────────────────────────────────────────

def emit_event(event_type: str, source: str, data: dict,
               subject: Optional[str] = None) -> dict:
    """
    Build a CloudEvents v1.0 envelope, store in ring buffer,
    and forward to sink (if configured).
    """
    if not event_type:
        raise ValueError("event_type required")
    if not source:
        source = "oxware/backend"
    event = _build_event(event_type, source, data or {}, subject)
    with _lock:
        _event_ring.append(event)
    _forward_to_sink(event)
    log.debug("cloudevent emitted: %s id=%s", event_type, event["id"])
    return event


def list_events(limit: int = 100) -> list:
    with _lock:
        events = list(_event_ring)
    events.sort(key=lambda e: e.get("time", ""), reverse=True)
    return events[:max(1, limit)]


def get_event(event_id: str) -> Optional[dict]:
    with _lock:
        for ev in _event_ring:
            if ev.get("id") == event_id:
                return ev
    return None


def configure_sink(url: str, fmt: str = "structured") -> dict:
    """Configure external event sink endpoint."""
    if fmt not in ("structured", "binary"):
        raise ValueError("format must be 'structured' or 'binary'")
    cfg = {
        "url":        url,
        "format":     fmt,
        "updated_at": int(time.time()),
    }
    with _lock:
        _save_sink(cfg)
    log.info("cloudevents sink configured: %s (%s)", url, fmt)
    return cfg


def get_sink() -> dict:
    with _lock:
        return _load_sink()


def get_event_types() -> list:
    """Return known OXware event types."""
    return OXWARE_EVENT_TYPES
