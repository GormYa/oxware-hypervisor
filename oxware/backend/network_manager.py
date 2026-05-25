import libvirt
import xml.etree.ElementTree as ET
import subprocess
import config

LIBVIRT_URI = config.LIBVIRT_URI


def _connect():
    return libvirt.open(LIBVIRT_URI)


def _safe_bridge_name(net):
    """Passthrough/macvtap ağlarda bridgeName() exception fırlatır — yakala."""
    try:
        return net.bridgeName() if net.isActive() else ""
    except Exception:
        return ""


def list_networks():
    conn = _connect()
    nets = []
    try:
        for net in conn.listAllNetworks():
            xml_str = net.XMLDesc()
            root = ET.fromstring(xml_str)

            forward = root.find("forward")
            ip_el = root.find("ip")
            dhcp_el = root.find(".//dhcp/range") if ip_el is not None else None

            nets.append({
                "uuid": net.UUIDString(),
                "name": net.name(),
                "active": bool(net.isActive()),
                "autostart": bool(net.autostart()),
                "bridge": _safe_bridge_name(net),
                "forward_mode": forward.get("mode", "nat") if forward is not None else "isolated",
                "ip": ip_el.get("address", "") if ip_el is not None else "",
                "netmask": ip_el.get("netmask", "") if ip_el is not None else "",
                "dhcp": {
                    "start": dhcp_el.get("start", "") if dhcp_el is not None else "",
                    "end": dhcp_el.get("end", "") if dhcp_el is not None else "",
                } if dhcp_el is not None else None,
            })
    finally:
        conn.close()
    return nets


def create_network(name, forward_mode="nat", bridge_name=None,
                   ip_address="192.168.100.1", netmask="255.255.255.0",
                   dhcp_start="192.168.100.100", dhcp_end="192.168.100.200",
                   bridge_iface=None):

    # Bridge / passthrough modu: fiziksel arayüzü doğrudan kullan
    # libvirt bridge modunda mevcut bir bridge aygıtı (br0 gibi) gerekir.
    # Fiziksel interface (ens160, enp1s0) için passthrough kullan — ayrı bridge kurmaya gerek yok.
    if forward_mode == "bridge":
        iface = bridge_iface or "enp1s0"
        xml = f"""<network>
  <name>{name}</name>
  <forward mode='passthrough'>
    <interface dev='{iface}'/>
  </forward>
</network>"""
        conn = _connect()
        try:
            net = conn.networkDefineXML(xml)
            net.setAutostart(1)
            net.create()
            return {"uuid": net.UUIDString(), "name": name, "status": "created", "mode": "passthrough"}
        finally:
            conn.close()

    if not bridge_name:
        bridge_name = f"virbr-{name[:8]}"

    forward_xml = ""
    if forward_mode in ("nat", "route"):
        forward_xml = f"<forward mode='{forward_mode}'/>"

    xml = f"""<network>
  <name>{name}</name>
  {forward_xml}
  <bridge name='{bridge_name}' stp='on' delay='0'/>
  <ip address='{ip_address}' netmask='{netmask}'>
    <dhcp>
      <range start='{dhcp_start}' end='{dhcp_end}'/>
    </dhcp>
  </ip>
</network>"""

    conn = _connect()
    try:
        net = conn.networkDefineXML(xml)
        net.setAutostart(1)
        net.create()
        return {"uuid": net.UUIDString(), "name": name, "status": "created"}
    finally:
        conn.close()


def delete_network(net_uuid):
    conn = _connect()
    try:
        try:
            net = conn.networkLookupByUUIDString(net_uuid)
        except libvirt.libvirtError:
            net = conn.networkLookupByName(net_uuid)

        if net.isActive():
            net.destroy()
        net.undefine()
        return {"status": "deleted"}
    finally:
        conn.close()


def start_network(net_uuid):
    conn = _connect()
    try:
        net = conn.networkLookupByUUIDString(net_uuid)
        net.create()
        return {"status": "started"}
    finally:
        conn.close()


def stop_network(net_uuid):
    conn = _connect()
    try:
        net = conn.networkLookupByUUIDString(net_uuid)
        net.destroy()
        return {"status": "stopped"}
    finally:
        conn.close()


def set_network_autostart(net_uuid, enabled: bool):
    conn = _connect()
    try:
        net = conn.networkLookupByUUIDString(net_uuid)
        net.setAutostart(1 if enabled else 0)
        return {"ok": True, "autostart": enabled}
    finally:
        conn.close()


def update_network(net_uuid: str, dhcp_start: str = None, dhcp_end: str = None,
                   ip_address: str = None, netmask: str = None) -> dict:
    """
    Edit a libvirt network's IP/DHCP config.
    Must stop → redefine → start because libvirt doesn't support live DHCP edits.
    """
    conn = _connect()
    try:
        net = conn.networkLookupByUUIDString(net_uuid)
        was_active = bool(net.isActive())
        was_autostart = bool(net.autostart())

        xml_str = net.XMLDesc(0)
        root = ET.fromstring(xml_str)

        ip_el = root.find("ip")
        if ip_el is not None:
            if ip_address:
                ip_el.set("address", ip_address)
            if netmask:
                ip_el.set("netmask", netmask)
            dhcp_el = ip_el.find("dhcp")
            if dhcp_el is not None:
                range_el = dhcp_el.find("range")
                if range_el is None:
                    range_el = ET.SubElement(dhcp_el, "range")
                if dhcp_start:
                    range_el.set("start", dhcp_start)
                if dhcp_end:
                    range_el.set("end", dhcp_end)
            elif dhcp_start and dhcp_end:
                dhcp_el = ET.SubElement(ip_el, "dhcp")
                range_el = ET.SubElement(dhcp_el, "range")
                range_el.set("start", dhcp_start)
                range_el.set("end", dhcp_end)

        new_xml = ET.tostring(root, encoding="unicode")

        # Stop → redefine → start
        if was_active:
            net.destroy()
        net.undefine()
        new_net = conn.networkDefineXML(new_xml)
        new_net.setAutostart(1 if was_autostart else 0)
        if was_active:
            new_net.create()

        return {
            "ok": True,
            "active": bool(new_net.isActive()),
            "autostart": bool(new_net.autostart()),
        }
    finally:
        conn.close()

def get_network_info(net_uuid):
    """Get detailed info for a single network."""
    conn = _connect()
    try:
        net = conn.networkLookupByUUIDString(net_uuid)
        import xml.etree.ElementTree as ET
        root = ET.fromstring(net.XMLDesc(0))
        ip_el = root.find("ip")
        dhcp_el = ip_el.find("dhcp") if ip_el is not None else None
        range_el = dhcp_el.find("range") if dhcp_el is not None else None
        return {
            "name": net.name(),
            "uuid": net_uuid,
            "active": bool(net.isActive()),
            "autostart": bool(net.autostart()),
            "bridge": net.bridgeName() if net.isActive() else "",
            "mode": root.findtext("forward/@mode") or (root.find("forward").get("mode") if root.find("forward") is not None else "nat"),
            "gateway": ip_el.get("address") if ip_el is not None else None,
            "netmask": ip_el.get("netmask") if ip_el is not None else None,
            "dhcp_start": range_el.get("start") if range_el is not None else None,
            "dhcp_end": range_el.get("end") if range_el is not None else None,
        }
    finally:
        conn.close()


def _read_sys(path: str, default="") -> str:
    try:
        with open(path) as f:
            return f.read().strip()
    except Exception:
        return default


def _parse_proc_net_dev() -> dict:
    """Parse /proc/net/dev → {iface: {rx_bytes, tx_bytes, rx_packets, tx_packets}}"""
    stats = {}
    try:
        with open("/proc/net/dev") as f:
            for line in f:
                parts = line.split()
                if ":" not in parts[0]:
                    continue
                iface = parts[0].rstrip(":")
                # columns: iface rx_bytes rx_packets rx_errs rx_drop ... tx_bytes ...
                stats[iface] = {
                    "rx_bytes":   int(parts[1]),
                    "rx_packets": int(parts[2]),
                    "tx_bytes":   int(parts[9]),
                    "tx_packets": int(parts[10]),
                }
    except Exception:
        pass
    return stats


def _iface_type(name: str) -> str:
    """Classify interface type from name and sysfs."""
    if name == "lo":
        return "loopback"
    if name.startswith("br") or name.startswith("virbr"):
        return "bridge"
    if name.startswith("vnet") or name.startswith("vif") or name.startswith("tap"):
        return "virtual"
    if name.startswith("bond"):
        return "bond"
    if "." in name:
        return "vlan"
    if name.startswith("wl"):
        return "wifi"
    if name.startswith("tun") or name.startswith("wg"):
        return "tunnel"
    return "ethernet"


def setup_host_bridge(bridge_name: str = "oxbr0", physical_iface: str = "enp1s0",
                      libvirt_net_name: str = "oxbridge") -> dict:
    """
    Host üzerinde Linux bridge oluştur ve libvirt'e kaydet.
    VMs bu bridge'e bağlanarak host NIC üzerinden doğrudan IP alır (gerçek IP izolasyonu).

    Adımlar:
    1. ip link add oxbr0 type bridge
    2. ip link set enp1s0 master oxbr0
    3. ip link set oxbr0 up
    4. libvirt'e bridge network tanımla (forward mode=bridge)
    """
    errors = []
    steps  = []

    # 1. Bridge oluştur (varsa atla)
    r = subprocess.run(["ip", "link", "show", bridge_name], capture_output=True)
    if r.returncode != 0:
        r2 = subprocess.run(
            ["ip", "link", "add", bridge_name, "type", "bridge"],
            capture_output=True, text=True
        )
        if r2.returncode == 0:
            steps.append(f"Bridge oluşturuldu: {bridge_name}")
        else:
            errors.append(f"Bridge oluşturulamadı: {r2.stderr.strip()}")
    else:
        steps.append(f"Bridge zaten var: {bridge_name}")

    # 2. Fiziksel NIC'i bridge'e ekle
    r3 = subprocess.run(
        ["ip", "link", "set", physical_iface, "master", bridge_name],
        capture_output=True, text=True
    )
    if r3.returncode == 0:
        steps.append(f"{physical_iface} → {bridge_name}")
    else:
        errors.append(f"NIC bridge'e eklenemedi: {r3.stderr.strip()}")

    # 3. Bridge'i aktif et
    subprocess.run(["ip", "link", "set", bridge_name, "up"], capture_output=True)
    steps.append(f"{bridge_name} UP")

    # 4. Libvirt bridge network tanımla
    xml = f"""<network>
  <name>{libvirt_net_name}</name>
  <forward mode='bridge'/>
  <bridge name='{bridge_name}'/>
</network>"""

    try:
        conn = _connect()
        try:
            # Varsa önce sil
            try:
                existing = conn.networkLookupByName(libvirt_net_name)
                if existing.isActive():
                    existing.destroy()
                existing.undefine()
            except Exception:
                pass

            net = conn.networkDefineXML(xml)
            net.setAutostart(1)
            net.create()
            steps.append(f"Libvirt network tanımlandı: {libvirt_net_name}")
        finally:
            conn.close()
    except Exception as e:
        errors.append(f"Libvirt network hatası: {e}")

    return {
        "ok": len(errors) == 0,
        "bridge": bridge_name,
        "physical_iface": physical_iface,
        "libvirt_network": libvirt_net_name,
        "steps": steps,
        "errors": errors,
        "info": (
            "VMs bu ağda oluşturulduğunda fiziksel NIC üzerinden doğrudan IP alır. "
            "Upstream DHCP veya cloud-init static IP kullanın."
        ),
    }


def list_host_bridges() -> list:
    """Host üzerindeki Linux bridge listesi."""
    result = subprocess.run(
        ["ip", "-j", "link", "show", "type", "bridge"],
        capture_output=True, text=True
    )
    bridges = []
    try:
        import json as _json
        data = _json.loads(result.stdout)
        for item in data:
            name = item.get("ifname", "")
            state = item.get("operstate", "UNKNOWN").lower()
            # Üyeleri bul
            r2 = subprocess.run(
                ["ip", "link", "show", "master", name],
                capture_output=True, text=True
            )
            members = []
            for line in r2.stdout.splitlines():
                parts = line.split(":")
                if len(parts) >= 2:
                    iface = parts[1].strip().split("@")[0].strip()
                    if iface and iface != name:
                        members.append(iface)
            bridges.append({"name": name, "state": state, "members": members})
    except Exception:
        pass
    return bridges


def _detect_primary_iface() -> str:
    """Detect primary physical interface from default route (e.g. ens160)."""
    result = subprocess.run(["ip", "route", "show", "default"],
                            capture_output=True, text=True)
    for line in result.stdout.splitlines():
        parts = line.split()
        if "dev" in parts:
            idx = parts.index("dev")
            if idx + 1 < len(parts):
                candidate = parts[idx + 1]
                # Skip virtual/bridge ifaces
                if not any(candidate.startswith(p) for p in
                           ("virbr", "vnet", "vif", "tap", "br", "lo", "tun", "wg")):
                    return candidate
    return "ens160"


def ensure_physnet() -> dict:
    """
    Ensure oxbridge (Linux bridge) or fallback network exists for VMs to reach
    the physical network.

    Priority:
    1. oxbridge already active in libvirt → return it
    2. oxbr0 Linux bridge exists on host → register with libvirt as oxbridge
    3. Any other passthrough/bridge libvirt network → return it
    4. Fallback: macvtap passthrough on detected interface (single-VM only)

    Never raises — caller logs result.
    """
    try:
        conn = _connect()
        try:
            # Priority 1: oxbridge already registered and active
            for net in conn.listAllNetworks():
                if net.name() == "oxbridge" and net.isActive():
                    return {"ok": True, "existing": True, "name": "oxbridge", "mode": "bridge"}

            # Priority 3: any other passthrough/bridge network
            _fallback = None
            for net in conn.listAllNetworks():
                if not net.isActive():
                    continue
                root = ET.fromstring(net.XMLDesc())
                forward = root.find("forward")
                if forward is not None and forward.get("mode") in (
                        "passthrough", "bridge", "private", "vepa"):
                    _fallback = {"ok": True, "existing": True,
                                 "name": net.name(), "mode": forward.get("mode")}
        finally:
            conn.close()
    except Exception as _e:
        return {"ok": False, "error": f"libvirt scan failed: {_e}"}

    # Priority 2: oxbr0 exists on host but not registered in libvirt
    _br_check = subprocess.run(["ip", "link", "show", "oxbr0"], capture_output=True)
    if _br_check.returncode == 0:
        _xml = """<network>
  <name>oxbridge</name>
  <forward mode='bridge'/>
  <bridge name='oxbr0'/>
</network>"""
        try:
            conn = _connect()
            try:
                # Remove stale unstarted definition if exists
                try:
                    _old = conn.networkLookupByName("oxbridge")
                    if not _old.isActive():
                        _old.undefine()
                except Exception:
                    pass
                net = conn.networkDefineXML(_xml)
                net.setAutostart(1)
                net.create()
                return {"ok": True, "created": True, "name": "oxbridge", "mode": "bridge"}
            finally:
                conn.close()
        except Exception as e:
            # oxbr0 exists but libvirt registration failed — still usable
            if _fallback:
                return _fallback
            return {"ok": False, "error": f"oxbridge register failed: {e}"}

    if _fallback:
        return _fallback

    # Priority 4: macvtap passthrough fallback (single-VM only, host can't reach VM)
    iface = _detect_primary_iface()
    try:
        result = create_network("physnet", forward_mode="bridge", bridge_iface=iface)
        result["created"] = True
        result["iface"] = iface
        result["warning"] = (
            "macvtap passthrough kullanılıyor — host VM'lere ulaşamaz. "
            "Kalıcı çözüm için install.sh çalıştırın (oxbr0 bridge kurar)."
        )
        return result
    except Exception as e:
        return {"ok": False, "error": str(e), "iface": iface}


def get_host_interfaces():
    result = subprocess.run(
        ["ip", "-j", "addr"],
        capture_output=True, text=True
    )
    interfaces = []
    _stats = _parse_proc_net_dev()
    try:
        import json
        ifaces = json.loads(result.stdout)
        for iface in ifaces:
            ifname = iface.get("ifname", "")
            addrs  = [
                a["local"]
                for a in iface.get("addr_info", [])
                if a.get("family") == "inet"
            ]
            addrs6 = [
                a["local"]
                for a in iface.get("addr_info", [])
                if a.get("family") == "inet6" and not a["local"].startswith("fe80")
            ]
            flags     = iface.get("flags", [])
            operstate = iface.get("operstate", "UNKNOWN").lower()
            # UNKNOWN operstate: VMware/virtual NICs report UNKNOWN even when active.
            if operstate in ("unknown", "") and "UP" in flags:
                operstate = "up"
            # Fallback: if has IP addresses, must be up
            if operstate not in ("up", "down") and addrs:
                operstate = "up"

            # Speed from sysfs (Mbps; -1 = unknown/virtual)
            speed_raw = _read_sys(f"/sys/class/net/{ifname}/speed")
            try:
                speed_mbps = int(speed_raw)
            except (ValueError, TypeError):
                speed_mbps = -1

            # Duplex
            duplex = _read_sys(f"/sys/class/net/{ifname}/duplex")

            # Driver via ethtool module path
            driver = _read_sys(f"/sys/class/net/{ifname}/device/driver/module/srcversion",
                               _read_sys(f"/sys/class/net/{ifname}/device/uevent", ""))
            # Simpler driver: just use modalias or skip
            driver = ""

            net_stats = _stats.get(ifname, {})

            interfaces.append({
                "name":       ifname,
                "state":      operstate,
                "mac":        iface.get("address", ""),
                "addresses":  addrs,
                "addresses6": addrs6,
                "flags":      flags,
                "mtu":        iface.get("mtu", 1500),
                "type":       _iface_type(ifname),
                "speed_mbps": speed_mbps if speed_mbps > 0 else None,
                "duplex":     duplex or None,
                "rx_bytes":   net_stats.get("rx_bytes", 0),
                "tx_bytes":   net_stats.get("tx_bytes", 0),
                "rx_packets": net_stats.get("rx_packets", 0),
                "tx_packets": net_stats.get("tx_packets", 0),
            })
    except Exception:
        pass
    return interfaces
