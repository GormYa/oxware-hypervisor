# OXware Hypervisor — ISO Builder

Bootable installer ISO oluşturur. Base: **Debian 12 Live Standard**.  
Boot flow (Proxmox VE ile aynı mantık): desktop yok, DM yok — direkt installer.

```
GRUB → live-boot → getty autologin root → startx
  → netcfg-gui.py  (Proxmox tarzı ağ yapılandırması)
  → Calamares fullscreen (OXware branding, Türkçe)
```

---

## Gereksinimler

| Gereksinim    | Değer                                         |
|---------------|-----------------------------------------------|
| Host OS       | Debian 12 veya Ubuntu 22.04+                  |
| Disk          | ≥ 15 GB boş alan                              |
| RAM           | ≥ 4 GB önerilen                               |
| Yetki         | `root` / `sudo`                               |
| Ağ            | Gerekli (chroot paketleri indirilir)          |

---

## Çalıştırma

```bash
sudo bash build/build-iso.sh
```

Çıktı:
```
OXware-Hypervisor-<versiyon>-amd64.iso        (~1.2 GB)
OXware-Hypervisor-<versiyon>-amd64.iso.sha256
```

---

## USB / Disk Yazma

**Linux:**
```bash
sudo dd if=OXware-Hypervisor-*.iso of=/dev/sdX bs=4M status=progress && sync
```

**Windows:** [Rufus](https://rufus.ie) veya [Ventoy](https://ventoy.net)

---

## Kurulum Adımları

ISO önyüklendiğinde:

1. **GRUB menüsü** — "Install" seç (5 saniye bekleme)
2. **Ağ Yapılandırması** — Interface, DHCP/Statik, Hostname, IP/GW/DNS
3. **Dil & Klavye** — Varsayılan: Türkçe / tr
4. **Disk Seçimi** — Tüm diski sil modu (erase)
5. **Kullanıcı** — Kullanıcı adı ve parola
6. **Özet** — Onayla ve kur
7. Kurulum biter, yeniden başlar
8. Web arayüzü: `https://<sunucu-ip>:8006`

---

## Dizin Yapısı

```
build/
├── build-iso.sh                    # Ana build scripti — root olarak çalıştır
├── VERSION                         # Otomatik artırılan patch versiyonu
│
├── calamares/                      # Calamares grafik installer config
│   ├── settings.conf               # Installer sırası ve branding referansı
│   ├── branding/
│   │   └── oxware/
│   │       ├── branding.desc       # Renkler, ürün adı, logo, URL'ler
│   │       └── show.qml            # QML slideshow (4 slayt, Ubuntu font)
│   └── modules/
│       ├── welcome.conf
│       ├── locale.conf             # tr_TR.UTF-8 varsayılan
│       ├── keyboard.conf
│       ├── partition.conf          # Erase-disk modu
│       ├── users.conf
│       ├── summary.conf
│       ├── finished.conf
│       └── oxware_install/
│           ├── module.desc         # Calamares Python job tanımı
│           └── main.py             # globalStorage → /tmp/oxware-netcfg.json
│                                   # + install.py --headless çağrısı
│
└── installer/
    ├── install.py                  # Headless kurulum backend (Calamares job çağırır)
    └── netcfg-gui.py               # Proxmox tarzı ağ config GUI (Calamares öncesi)
```

---

## Installer Mimarisi

```
Boot ISO
  └── getty@tty1 autologin root
        └── /root/.bash_profile  →  startx oxware-start.sh
              │
              ├── netcfg-gui.py          ← Ağ config (DHCP/Statik, hostname)
              │     └── /tmp/oxware-netcfg.json
              │
              └── /usr/bin/calamares (fullscreen, OXware branding)
                    ├── Show: welcome / locale / keyboard / partition / users / summary
                    ├── Exec: oxware_install (Python job)
                    │         ├── /tmp/oxware-netcfg.json  ← ağ ayarları
                    │         └── install.py --headless    ← debootstrap + KVM + GRUB
                    └── Show: finished → reboot
```

---

## Hata Ayıklama

Kurulum sorununda ISO içinden:

```bash
# Calamares log
cat /tmp/calamares.log

# Ağ config GUI log
cat /tmp/netcfg-gui.log

# Başlatma log
cat /tmp/oxware-start.log

# Calamares manuel başlat
DISPLAY=:0 calamares -D 6
```

---

## ISO Rebuild

Değişiklik sonrası ISO yeniden oluşturmak için:

```bash
sudo oxupdate                   # sunucudaki repoyu güncelle
sudo bash build/build-iso.sh    # ISO yeniden derle
```

Önceki ISO'lar otomatik silinir, sadece son versiyon kalır.
