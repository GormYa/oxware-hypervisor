"""
OXware Confidential VM — AMD SEV / Intel TDX
─────────────────────────────────────────────
Memory-encrypted confidential VMs.
- AMD SEV (Secure Encrypted Virtualization) — qemu launch-security type='sev'
- AMD SEV-SNP (Secure Nested Paging) — sev-snp
- Intel TDX (Trust Domain Extensions) — tdx
- Detection via /sys/module/kvm_amd/parameters/sev + cpuid

Persists policy at /var/lib/oxware/confidential_vm.json
"""
from __future__ import annotations
import os, json, logging, subprocess
from pathlib import Path

log = logging.getLogger("confidential_vm")
_CFG = Path("/var/lib/oxware/confidential_vm.json")


def detect_support() -> dict:
    """Detect host CPU + kernel support."""
    out = {"sev": False, "sev_es": False, "sev_snp": False, "tdx": False, "details": {}}
    try:
        for name, path in [
            ("sev",      "/sys/module/kvm_amd/parameters/sev"),
            ("sev_es",   "/sys/module/kvm_amd/parameters/sev_es"),
            ("sev_snp",  "/sys/module/kvm_amd/parameters/sev_snp"),
            ("tdx",      "/sys/module/kvm_intel/parameters/tdx"),
        ]:
            try:
                v = Path(path).read_text().strip()
                out[name] = v in ("Y", "1", "y", "true")
                out["details"][name] = v
            except Exception:
                pass
    except Exception as e:
        log.warning("detect_support: %s", e)
    # CPUID quick check (best-effort)
    try:
        r = subprocess.run(["cat", "/proc/cpuinfo"], capture_output=True, text=True, timeout=3)
        if "sev" in r.stdout.lower(): out["details"]["cpu_sev_flag"] = True
        if "tdx" in r.stdout.lower(): out["details"]["cpu_tdx_flag"] = True
    except Exception:
        pass
    return out


def _load() -> dict:
    try:
        if _CFG.exists():
            return json.loads(_CFG.read_text(encoding="utf-8"))
    except Exception:
        pass
    return {"vms": {}}


def _save(d: dict):
    _CFG.parent.mkdir(parents=True, exist_ok=True)
    _CFG.write_text(json.dumps(d, indent=2), encoding="utf-8")


def list_protected_vms() -> list:
    return [{"vm_id": k, **v} for k, v in _load().get("vms", {}).items()]


def enable_for_vm(vm_id: str, mode: str = "sev") -> dict:
    """Mark VM as confidential — actual libvirt XML injection
    must be performed at VM creation/edit time by vm_manager."""
    if mode not in ("sev", "sev-es", "sev-snp", "tdx"):
        return {"ok": False, "error": f"unsupported mode: {mode}"}
    d = _load()
    d.setdefault("vms", {})[vm_id] = {"mode": mode, "enabled": True}
    _save(d)
    log.info("confidential_vm enabled: %s (%s)", vm_id, mode)
    return {"ok": True, "vm_id": vm_id, "mode": mode}


def disable_for_vm(vm_id: str) -> dict:
    d = _load()
    if vm_id in d.get("vms", {}):
        del d["vms"][vm_id]
        _save(d)
    return {"ok": True, "vm_id": vm_id}


def get_vm_config(vm_id: str) -> dict:
    return _load().get("vms", {}).get(vm_id, {"enabled": False})


def generate_libvirt_xml_snippet(mode: str, policy_hex: str = "0x0001") -> str:
    """Return XML to inject into <launchSecurity> for libvirt."""
    if mode == "tdx":
        return '<launchSecurity type="tdx"/>'
    # SEV / SEV-ES / SEV-SNP
    return (f'<launchSecurity type="sev">\n'
            f'  <policy>{policy_hex}</policy>\n'
            f'  <cbitpos>47</cbitpos>\n'
            f'  <reducedPhysBits>1</reducedPhysBits>\n'
            f'</launchSecurity>')
