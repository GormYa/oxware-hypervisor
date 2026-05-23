"""
vTPM Manager — Libvirt TPM passthrough + emulated (swtpm) support.
"""
import subprocess
import xml.etree.ElementTree as ET
import libvirt

def _connect():
    import config
    return libvirt.open(config.LIBVIRT_URI)

def list_vm_tpm(vm_id: str) -> dict:
    """Return current TPM config for a VM."""
    conn = _connect()
    try:
        dom = conn.lookupByName(vm_id)
        root = ET.fromstring(dom.XMLDesc(0))
        tpm = root.find(".//tpm")
        if tpm is None:
            return {"has_tpm": False}
        return {
            "has_tpm": True,
            "model": tpm.get("model", "tpm-tis"),
            "backend": tpm.find("backend").get("type") if tpm.find("backend") is not None else "unknown",
            "version": tpm.find("backend").get("version", "2.0") if tpm.find("backend") is not None else "2.0",
        }
    finally:
        conn.close()

def add_vtpm(vm_id: str, model: str = "tpm-tis", version: str = "2.0") -> dict:
    """Add emulated vTPM to VM. Requires swtpm installed on host."""
    # Check swtpm available
    r = subprocess.run(["which", "swtpm"], capture_output=True)
    if r.returncode != 0:
        return {"ok": False, "error": "swtpm not installed. Run: apt install swtpm swtpm-tools"}

    conn = _connect()
    try:
        dom = conn.lookupByName(vm_id)
        was_active = dom.isActive()
        root = ET.fromstring(dom.XMLDesc(0))

        # Remove existing TPM if any
        devices = root.find("devices")
        for tpm in devices.findall("tpm"):
            devices.remove(tpm)

        # Add emulated TPM
        tpm_el = ET.SubElement(devices, "tpm")
        tpm_el.set("model", model)
        backend = ET.SubElement(tpm_el, "backend")
        backend.set("type", "emulator")
        backend.set("version", version)

        conn.defineXML(ET.tostring(root, encoding="unicode"))
        return {"ok": True, "model": model, "version": version, "backend": "emulator",
                "note": "VM restart required for TPM to activate"}
    finally:
        conn.close()

def remove_vtpm(vm_id: str) -> dict:
    """Remove vTPM from VM."""
    conn = _connect()
    try:
        dom = conn.lookupByName(vm_id)
        root = ET.fromstring(dom.XMLDesc(0))
        devices = root.find("devices")
        removed = 0
        for tpm in devices.findall("tpm"):
            devices.remove(tpm)
            removed += 1
        conn.defineXML(ET.tostring(root, encoding="unicode"))
        return {"ok": True, "removed": removed}
    finally:
        conn.close()

def check_swtpm() -> dict:
    """Check if swtpm is available on host."""
    r = subprocess.run(["which", "swtpm"], capture_output=True, text=True)
    r2 = subprocess.run(["swtpm", "--version"], capture_output=True, text=True)
    return {
        "available": r.returncode == 0,
        "path": r.stdout.strip(),
        "version": r2.stdout.strip().split("\n")[0] if r2.returncode == 0 else None,
    }
