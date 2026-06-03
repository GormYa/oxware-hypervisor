"""
OXware Plugin SDK
━━━━━━━━━━━━━━━
Load Python plugins from /opt/oxware/plugins/<name>/plugin.py
Each plugin: metadata dict + optional register_routes(app) + optional on_vm_event(event)
"""
import importlib.util
import json
import logging
import sys
import threading
from dataclasses import dataclass, asdict
from pathlib import Path

_log = logging.getLogger("oxware.plugin_sdk")

_PLUGINS_DIR = Path("/opt/oxware/plugins")
_STATE_FILE = Path("/var/lib/oxware/plugins.json")
_lock = threading.Lock()

_registry: dict[str, dict] = {}  # plugin_id -> {manifest, module}


@dataclass
class PluginManifest:
    id: str
    name: str
    version: str
    author: str
    description: str
    api_version: str
    enabled: bool


def _load_state() -> dict:
    try:
        if _STATE_FILE.exists():
            return json.loads(_STATE_FILE.read_text())
    except Exception:
        pass
    return {}


def _save_state(data: dict):
    _STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    _STATE_FILE.write_text(json.dumps(data, indent=2))


def load_plugin(plugin_dir: Path, app=None) -> dict:
    plugin_py = plugin_dir / "plugin.py"
    if not plugin_py.exists():
        raise FileNotFoundError(f"plugin.py not found in {plugin_dir}")

    spec = importlib.util.spec_from_file_location(
        f"oxware_plugin_{plugin_dir.name}", plugin_py
    )
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception as e:
        raise RuntimeError(f"Failed to load plugin {plugin_dir.name}: {e}") from e

    meta = getattr(module, "PLUGIN_META", None)
    if not meta or not isinstance(meta, dict):
        raise ValueError(f"Plugin {plugin_dir.name} missing PLUGIN_META dict")

    state = _load_state()
    plugin_id = meta.get("id", plugin_dir.name)
    enabled = state.get(plugin_id, {}).get("enabled", meta.get("enabled", True))

    manifest = PluginManifest(
        id=plugin_id,
        name=meta.get("name", plugin_dir.name),
        version=meta.get("version", "0.1.0"),
        author=meta.get("author", "unknown"),
        description=meta.get("description", ""),
        api_version=meta.get("api_version", "1.0"),
        enabled=enabled,
    )

    if app is not None and enabled and hasattr(module, "register_routes"):
        try:
            module.register_routes(app)
        except Exception as e:
            _log.warning("Plugin %s register_routes failed: %s", plugin_id, e)

    entry = {"manifest": asdict(manifest), "module": module}
    with _lock:
        _registry[plugin_id] = entry

    return asdict(manifest)


def load_all_plugins(app=None) -> list:
    results = []
    if not _PLUGINS_DIR.exists():
        return results
    for d in sorted(_PLUGINS_DIR.iterdir()):
        if not d.is_dir():
            continue
        try:
            m = load_plugin(d, app=app)
            results.append(m)
        except Exception as e:
            _log.warning("Skipping plugin %s: %s", d.name, e)
    return results


def get_plugin(plugin_id: str) -> dict:
    with _lock:
        entry = _registry.get(plugin_id)
    if not entry:
        raise KeyError(f"Plugin '{plugin_id}' not loaded")
    return entry["manifest"]


def list_plugins() -> list:
    with _lock:
        return [e["manifest"] for e in _registry.values()]


def _set_enabled(plugin_id: str, enabled: bool) -> dict:
    with _lock:
        state = _load_state()
        state.setdefault(plugin_id, {})["enabled"] = enabled
        _save_state(state)
        if plugin_id in _registry:
            _registry[plugin_id]["manifest"]["enabled"] = enabled
        manifest = _registry.get(plugin_id, {}).get("manifest", {"id": plugin_id, "enabled": enabled})
    return manifest


def enable_plugin(plugin_id: str) -> dict:
    return _set_enabled(plugin_id, True)


def disable_plugin(plugin_id: str) -> dict:
    return _set_enabled(plugin_id, False)


def emit_event(event_type: str, data: dict):
    event = {"type": event_type, "data": data}
    with _lock:
        entries = list(_registry.values())
    for entry in entries:
        manifest = entry["manifest"]
        if not manifest.get("enabled", True):
            continue
        module = entry.get("module")
        if module is None or not hasattr(module, "on_vm_event"):
            continue
        try:
            module.on_vm_event(event)
        except Exception as e:
            _log.warning("Plugin %s on_vm_event error: %s", manifest["id"], e)


def get_plugin_template() -> str:
    return '''\
"""
OXware Plugin — <plugin name>
Replace PLUGIN_META fields and implement handlers below.
"""

PLUGIN_META = {
    "id": "my_plugin",
    "name": "My Plugin",
    "version": "1.0.0",
    "author": "Your Name",
    "description": "Short description of what this plugin does.",
    "api_version": "1.0",
    "enabled": True,
}


def register_routes(app):
    """Register Flask routes. Called once at startup if plugin is enabled."""
    @app.route("/plugins/my_plugin/hello")
    def my_plugin_hello():
        return {"message": "Hello from my_plugin"}


def on_vm_event(event):
    """
    Called for every VM event emitted via plugin_sdk.emit_event().
    event = {"type": str, "data": dict}
    """
    pass
'''
