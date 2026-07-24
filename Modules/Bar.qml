import Quickshell // for PanelWindow
import QtQuick // for Text
import Quickshell.Io
import QtQuick.Shapes
import qs.Widgets.Bar
import Quickshell.Wayland
import qs.Services
import qs.Commons
import qs.Widgets.General
import Qt5Compat.GraphicalEffects

Scope {
    id: scope
    
    Variants {
        model: Quickshell.screens;
        delegate: Component {
            PanelWindow {
                Component.onCompleted: {
                    if (this.WlrLayershell != null) {
                        this.WlrLayershell.layer = WlrLayer.Top;
                        this.WlrLayershell.namespace = "mybar"
                    }
                }
                id: root
                required property var modelData
                screen: modelData
                color: "transparent"
                margins {
                    top: 5
                    bottom: 5
                    left: 5
                    right: 5
                }

                anchors {
                    top: true
                    left: true
                    right: true
                }

                implicitHeight: 45
                property int height: (root.implicitHeight / 2) + 5

                Rectangle {
                    id: mainContainer
                    // Extraer colores de Singleton
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Qt.alpha(Colors.palette[0], 0.35) }
                        GradientStop { position: 0.5; color: Qt.alpha(Colors.palette[5], 0.35) }
                        GradientStop { position: 1.0; color: Qt.alpha(Colors.palette[0], 0.35) }

                    }
                    border.color: Qt.alpha(Colors.palette[7], 0.5)
                    anchors.left: parent.left
                    anchors.right: parent.right

                    height: root.implicitHeight
                    radius: 30

                    // Rectangulo izquierdo
                    LeftSide { id: leftside; radius: 10; barWindow: root; barHeight: root.height }

                    // Rectangulo central
                    MidSide{ id: midside; barHeight: root.height }

                    // Rectangulo derecho
                    RightSide {id: rightside; radius: 10; barHeight: root.height}
                }

                // Los contenidos de los popups van en Loader perezosos
                // (active: contentActive): se instancian al abrir y se
                // destruyen tras el fade de cierre. Antes existían SIEMPRE
                // ×3 monitores (AlbumArt con shaders, ~21 miniaturas del
                // grid, listas...) y eran el mayor costo de RAM en reposo.
                PanelPopup {
                    id: spotifyPopup
                    alignItem: rightside
                    show: PopupState.isOpenOn("spotify", root.screen)
                    panelColor: [SpotifyInfo.albumPalette[4], SpotifyInfo.albumPalette[2]]
                    offsetX: -70 // hacia el centro de la barra; ajustar a gusto
                    panelWidth: 500

                    Loader {
                        anchors.fill: parent
                        active: spotifyPopup.contentActive
                        sourceComponent: Component {
                            SpotifyAll {
                                anchors.fill: parent
                                accent: SpotifyInfo.albumPalette[4]
                            }
                        }
                    }
                }

                PanelPopup {
                    id: wallpaperPopup
                    alignItem: midside
                    show: PopupState.isOpenOn("wallpaper", root.screen)
                    grabKeyboardFocus: true
                    onDismissed: PopupState.active = ""
                    panelColor: Colors.palette[4]
                    panelHeight: 380
                    panelWidth: 640

                    Loader {
                        anchors.fill: parent
                        anchors.margins: 12
                        active: wallpaperPopup.contentActive
                        sourceComponent: Component {
                            WallpaperGrid { anchors.fill: parent }
                        }
                    }
                }

                PanelPopup {
                    id: wifiPopup
                    alignItem: leftside
                    show: PopupState.isOpenOn("wifi", root.screen)
                    // Con grab: el campo de contraseña necesita teclado real
                    grabKeyboardFocus: true
                    onDismissed: PopupState.active = ""
                    panelColor: Colors.palette[4]
                    panelHeight: 360
                    offsetX: 40 // hacia el centro de la barra; ajustar a gusto

                    Loader {
                        anchors.fill: parent
                        anchors.margins: 12
                        active: wifiPopup.contentActive
                        sourceComponent: Component {
                            WifiNetworkList { anchors.fill: parent }
                        }
                    }
                }

                PanelPopup {
                    id: bluetoothPopup
                    alignItem: leftside
                    show: PopupState.isOpenOn("bluetooth", root.screen)
                    panelColor: Colors.palette[4]
                    panelHeight: 320
                    offsetX: 20 // hacia el centro de la barra; ajustar a gusto

                    Loader {
                        anchors.fill: parent
                        anchors.margins: 12
                        active: bluetoothPopup.contentActive
                        sourceComponent: Component {
                            BluetoothDeviceList { anchors.fill: parent }
                        }
                    }
                }

                PanelPopup {
                    id: notificationsPopup
                    alignItem: rightside
                    show: PopupState.isOpenOn("notifications", root.screen)
                    panelColor: Colors.palette[4]
                    panelHeight: 400
                    panelWidth: 360
                    offsetX: -60 // hacia el centro de la barra; ajustar a gusto

                    onShowChanged: if (show) NotificationService.markAllRead()

                    Loader {
                        anchors.fill: parent
                        anchors.margins: 12
                        active: notificationsPopup.contentActive
                        sourceComponent: Component {
                            NotificationList { anchors.fill: parent }
                        }
                    }
                }

                PanelPopup {
                    id: powerPopup
                    alignItem: rightside
                    show: PopupState.isOpenOn("power", root.screen)
                    panelColor: Colors.palette[4]
                    panelHeight: 208 // 4 filas × 40 + 3 × 8 spacing + 2 × 12 margins
                    panelWidth: 220
                    offsetX: 20 // hacia el centro de la barra; ajustar a gusto

                    // Nota: ya no hace falta disarm() al cerrar — el contenido
                    // se destruye con el Loader y el doble-click de
                    // confirmación nace desarmado en cada apertura.
                    Loader {
                        anchors.fill: parent
                        anchors.margins: 12
                        active: powerPopup.contentActive
                        sourceComponent: Component {
                            PowerMenu { anchors.fill: parent }
                        }
                    }
                }
            }
        }
    }
}
