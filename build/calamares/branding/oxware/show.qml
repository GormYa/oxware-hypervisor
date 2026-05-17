/* OXware Hypervisor — Calamares installer slideshow
   Proxmox tarzı: koyu mavi arka plan, logo merkez, Türkçe */
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation
    timer.interval: 5000

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#0a1628" }
                GradientStop { position: 1.0; color: "#0d2340" }
            }
            Column {
                anchors.centerIn: parent
                spacing: 24
                Image {
                    source: "oxware_logo.png"
                    height: 72
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                    smooth: true
                }
                Text {
                    text: "OXware Hypervisor 2.0"
                    color: "#ffffff"
                    font.pixelSize: 30
                    font.weight: Font.Light
                    font.letterSpacing: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "KVM · QEMU · libvirt"
                    color: "#4a8ec2"
                    font.pixelSize: 14
                    font.letterSpacing: 3
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Rectangle {
                    width: 120; height: 2
                    color: "#1565c0"
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Sistem kuruluyor, lütfen bekleyin..."
                    color: "#5b8ab8"
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
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#0a1628" }
                GradientStop { position: 1.0; color: "#0d2340" }
            }
            Column {
                anchors.centerIn: parent
                spacing: 16
                width: 520
                Image {
                    source: "oxware_icon.png"
                    height: 40
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                    smooth: true
                }
                Text {
                    text: "Yüksek Performans Sanallaştırma"
                    color: "#5b9bd5"
                    font.pixelSize: 22
                    font.weight: Font.Medium
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.letterSpacing: 0.5
                }
                Rectangle { width: 80; height: 2; color: "#1565c0"; anchors.horizontalCenter: parent.horizontalCenter }
                Text {
                    text: "KVM donanım hızlandırması ile fiziksel sunucunuzu\ntam kapasite sanal makine olarak kullanın."
                    color: "#b0cde8"
                    font.pixelSize: 14
                    lineHeight: 1.5
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Repeater {
                        model: [
                            "● CPU pinning ve NUMA desteği",
                            "● VirtIO ağ / disk sürücüleri",
                            "● PCIe passthrough (GPU, NIC)",
                            "● Anlık snapshot ve klonlama"
                        ]
                        Text {
                            text: modelData
                            color: "#7faed4"
                            font.pixelSize: 13
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#0a1628" }
                GradientStop { position: 1.0; color: "#0d2340" }
            }
            Column {
                anchors.centerIn: parent
                spacing: 16
                width: 520
                Image {
                    source: "oxware_icon.png"
                    height: 40
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                    smooth: true
                }
                Text {
                    text: "Web Tabanlı Yönetim Paneli"
                    color: "#5b9bd5"
                    font.pixelSize: 22
                    font.weight: Font.Medium
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.letterSpacing: 0.5
                }
                Rectangle { width: 80; height: 2; color: "#1565c0"; anchors.horizontalCenter: parent.horizontalCenter }
                Text {
                    text: "Tüm sanal makinelerinizi tarayıcı üzerinden\nhızlı ve güvenli şekilde yönetin."
                    color: "#b0cde8"
                    font.pixelSize: 14
                    lineHeight: 1.5
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Repeater {
                        model: [
                            "● HTTPS güvenli web arayüzü",
                            "● Gerçek zamanlı kaynak izleme",
                            "● noVNC konsol erişimi",
                            "● WiseCP / WHMCS entegrasyonu"
                        ]
                        Text {
                            text: modelData
                            color: "#7faed4"
                            font.pixelSize: 13
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }
    }

    Slide {
        anchors.fill: parent
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#0a1628" }
                GradientStop { position: 1.0; color: "#0d2340" }
            }
            Column {
                anchors.centerIn: parent
                spacing: 16
                width: 520
                Image {
                    source: "oxware_icon.png"
                    height: 40
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                    smooth: true
                }
                Text {
                    text: "Kurumsal Güvenlik"
                    color: "#5b9bd5"
                    font.pixelSize: 22
                    font.weight: Font.Medium
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.letterSpacing: 0.5
                }
                Rectangle { width: 80; height: 2; color: "#1565c0"; anchors.horizontalCenter: parent.horizontalCenter }
                Text {
                    text: "İki faktörlü kimlik doğrulama, şifreli iletişim\nve rol tabanlı erişim kontrolü."
                    color: "#b0cde8"
                    font.pixelSize: 14
                    lineHeight: 1.5
                    horizontalAlignment: Text.AlignHCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Repeater {
                        model: [
                            "● TOTP iki faktörlü doğrulama",
                            "● TLS 1.2+ zorunlu şifreleme",
                            "● PBKDF2 şifre hashleme",
                            "● API anahtarı yönetimi"
                        ]
                        Text {
                            text: modelData
                            color: "#7faed4"
                            font.pixelSize: 13
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }
    }
}
