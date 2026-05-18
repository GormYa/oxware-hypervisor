#!/usr/bin/env python3
"""
OXware Calamares Job Module
Reads globalStorage selections → writes JSON config → calls install.py --headless
"""

import os
import json
import subprocess
import tempfile

import libcalamares


CONFIG_PATH  = "/tmp/oxware-install-config.json"
INSTALLER    = "/opt/oxware-installer/install.py"
NETCFG_PATH  = "/tmp/oxware-netcfg.json"


def pretty_name():
    return "OXware Hypervisor kurulumu"


def _gs_get(key, default=None):
    val = libcalamares.globalstorage.value(key)
    return val if val is not None else default


def _build_config():
    """Extract Calamares globalStorage values into install.py headless config."""

    # ── Disk ──────────────────────────────────────────────────────────────────
    install_path = _gs_get("rootMountPoint", "/mnt/target")

    # Calamares stores chosen device in partitions list or install_path device
    disk = ""
    partitions = _gs_get("partitions", [])
    if partitions:
        # First partition's device (strip trailing digit)
        dev = partitions[0].get("device", "")
        if dev:
            # /dev/sda1 → /dev/sda
            import re
            m = re.match(r"(/dev/[a-z]+)", dev)
            disk = m.group(1) if m else dev
    if not disk:
        # Fallback: globalStorage "selectedDriveName"
        disk = _gs_get("selectedDriveName", "")
    if not disk:
        disk = _gs_get("installDevice", "")

    # ── Locale / timezone ────────────────────────────────────────────────────
    locale_conf = _gs_get("localeConf", {})
    locale   = locale_conf.get("LANG", "tr_TR.UTF-8") if isinstance(locale_conf, dict) else "tr_TR.UTF-8"
    timezone = _gs_get("locationRegion", "Europe") + "/" + _gs_get("locationZone", "Istanbul")

    # ── Keyboard ─────────────────────────────────────────────────────────────
    kb_layout  = _gs_get("keyboardLayout",  "tr")
    kb_variant = _gs_get("keyboardVariant", "")
    if isinstance(kb_layout, dict):
        kb_layout = kb_layout.get("key", "tr")

    # ── Users ─────────────────────────────────────────────────────────────────
    username = _gs_get("username", "oxadmin")
    password = _gs_get("password", "")
    if not password:
        password = _gs_get("userPassword", "")
    hostname = _gs_get("hostname", "oxware-node")
    if not hostname:
        hostname = "oxware-node"

    return {
        "disk":             disk,
        "hostname":         hostname,
        "username":         username,
        "password":         password,
        "net_mode":         "dhcp",
        "keyboard_layout":  kb_layout,
        "keyboard_variant": kb_variant,
        "locale":           locale,
        "timezone":         timezone,
        "ssh_enabled":      True,
        "ssh_port":         22,
        "ssh_root":         False,
        "ssh_passwd_auth":  True,
    }


def _read_netcfg():
    """netcfg-gui.py tarafından kayıt edilen ağ yapılandırmasını oku."""
    if not os.path.exists(NETCFG_PATH):
        return {}
    try:
        with open(NETCFG_PATH) as f:
            data = json.load(f)
        libcalamares.utils.debug(f"oxware_install: netcfg = {json.dumps(data)}")
        return data
    except Exception as e:
        libcalamares.utils.debug(f"oxware_install: netcfg okuma hatası: {e}")
        return {}


def run():
    libcalamares.utils.debug("oxware_install: başlıyor")

    if not os.path.exists(INSTALLER):
        return (
            "Installer bulunamadı",
            f"{INSTALLER} mevcut değil. ISO doğru oluşturuldu mu?",
        )

    cfg = _build_config()

    # netcfg-gui.py değerlerini Calamares globalStorage üzerine yaz
    net = _read_netcfg()
    if net:
        # Hostname: netcfg-gui öncelikli (daha erken ve açık biçimde girildi)
        if net.get("hostname"):
            cfg["hostname"] = net["hostname"]
        # Ağ modu
        mode = net.get("mode", "dhcp")
        cfg["net_mode"] = mode
        if mode == "static":
            cfg["net_ip"]   = net.get("ip",      "")
            cfg["net_mask"] = net.get("netmask",  "255.255.255.0")
            cfg["net_gw"]   = net.get("gateway",  "")
            cfg["net_dns"]  = net.get("dns1",     "8.8.8.8")

    if not cfg["disk"]:
        return (
            "Disk seçilmedi",
            "Hedef disk tespit edilemedi. Partition sayfasına dönüp diski seçin.",
        )

    libcalamares.utils.debug(f"oxware_install: config = {json.dumps(cfg, indent=2)}")

    with open(CONFIG_PATH, "w") as f:
        json.dump(cfg, f)

    libcalamares.job.setprogress(0.01)

    try:
        proc = subprocess.Popen(
            ["python3", INSTALLER, "--headless", CONFIG_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            libcalamares.utils.debug(f"installer: {line}")
            try:
                data = json.loads(line)
                pct  = data.get("pct", 0)
                msg  = data.get("msg", "")
                if pct:
                    libcalamares.job.setprogress(max(0.01, min(0.99, pct / 100.0)))
                if msg:
                    libcalamares.utils.debug(f"progress {pct}%: {msg}")
                if data.get("error"):
                    return ("Kurulum hatası", data["error"])
                if data.get("done") and pct >= 100:
                    break
            except json.JSONDecodeError:
                libcalamares.utils.debug(f"installer stdout: {line}")

        proc.wait()
        if proc.returncode != 0:
            return (
                "Kurulum başarısız",
                f"install.py exit code {proc.returncode}. /tmp/calamares-install.log dosyasını kontrol edin.",
            )

    except Exception as exc:
        return ("Kurulum istisnası", str(exc))
    finally:
        try:
            os.unlink(CONFIG_PATH)
        except OSError:
            pass

    libcalamares.job.setprogress(1.0)
    return None
