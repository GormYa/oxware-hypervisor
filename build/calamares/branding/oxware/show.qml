/* OXware Hypervisor — Calamares slideshow */
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation
    timer.interval: 4500

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            color: "#0d2340"
            Column {
                anchors.centerIn: parent
                spacing: 20
                Image {
                    source: "oxware_logo.png"
                    height: 64
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "OXware Hypervisor"
                    color: "#ffffff"
                    font.pixelSize: 32
                    font.weight: Font.Light
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "KVM/QEMU tabanlı kurumsal sanallaştırma platformu"
                    color: "#7faed4"
                    font.pixelSize: 16
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Kurulum devam ediyor, lütfen bekleyin..."
                    color: "#4a7fa8"
                    font.pixelSize: 13
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            color: "#0d2340"
            Column {
                anchors.centerIn: parent
                spacing: 18
                width: 500
                Text {
                    text: "⚡  KVM Sanallaştırma"
                    color: "#5b9bd5"
                    font.pixelSize: 26
                    font.weight: Font.Medium
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Donanım hızlandırmalı KVM/QEMU altyapısı ile\nfiziksel sunucunuzu tam performansta çalıştırın."
                    color: "#c5d8f0"
                    font.pixelSize: 15
                    lineHeight: 1.4
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Rectangle { height: 1; width: 200; color: "#1565c0"; anchors.horizontalCenter: parent.horizontalCenter }
                Text {
                    text: "• CPU pinning & NUMA support\n• VirtIO disk/network\n• PCIe passthrough (GPU, NIC)\n• Anlık snapshot & klonlama"
                    color: "#7faed4"
                    font.pixelSize: 14
                    lineHeight: 1.5
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            color: "#0d2340"
            Column {
                anchors.centerIn: parent
                spacing: 18
                width: 500
                Text {
                    text: "🌐  Web Yönetim Arayüzü"
                    color: "#5b9bd5"
                    font.pixelSize: 26
                    font.weight: Font.Medium
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Tarayıcı tabanlı modern arayüz ile\ntüm sanal makinelerinizi tek noktadan yönetin."
                    color: "#c5d8f0"
                    font.pixelSize: 15
                    lineHeight: 1.4
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Rectangle { height: 1; width: 200; color: "#1565c0"; anchors.horizontalCenter: parent.horizontalCenter }
                Text {
                    text: "• HTTPS güvenli erişim\n• Gerçek zamanlı izleme\n• noVNC konsol erişimi\n• REST API & WiseCP/WHMCS entegrasyonu"
                    color: "#7faed4"
                    font.pixelSize: 14
                    lineHeight: 1.5
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            color: "#0d2340"
            Column {
                anchors.centerIn: parent
                spacing: 18
                width: 500
                Text {
                    text: "🔒  Kurumsal Güvenlik"
                    color: "#5b9bd5"
                    font.pixelSize: 26
                    font.weight: Font.Medium
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "İki faktörlü kimlik doğrulama, rol tabanlı\nyetkilendirme ve şifreli iletişim."
                    color: "#c5d8f0"
                    font.pixelSize: 15
                    lineHeight: 1.4
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Rectangle { height: 1; width: 200; color: "#1565c0"; anchors.horizontalCenter: parent.horizontalCenter }
                Text {
                    text: "• TOTP 2FA\n• PBKDF2 şifre hashleme\n• TLS 1.2+ zorunlu\n• API anahtarı yetkilendirme"
                    color: "#7faed4"
                    font.pixelSize: 14
                    lineHeight: 1.5
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }
}
