pragma ComponentBehavior: Bound
import Quickshell // for PanelWindow
import QtQuick // for Text
import QtQuick.Shapes
import QtQuick.Window
import qs.Widgets.Bar
import Quickshell.Wayland
import qs.Services
import qs.Commons
import qs.Widgets.General

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

                Item {
                    id: mainContainer
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: root.implicitHeight

                    // Muesca sobre el popup abierto (solo en la barra de su monitor)
                    readonly property real notchHalfWidth: PopupState.notchHalfWidth
                    readonly property real notchDepth: PopupState.notchDepth
                    readonly property bool notchOn: PopupState.notchItem !== null
                        && PopupState.notchItem.Window.window === mainContainer.Window.window
                    property real notchCenter: 0
                    function updateNotch() {
                        // Al cerrar no se actualiza: la muesca se aplana donde estaba
                        if (notchOn) notchCenter = PopupState.notchItem.mapToItem(mainContainer, PopupState.notchX, 0).x
                    }
                    onNotchOnChanged: updateNotch()
                    Connections {
                        target: PopupState
                        function onNotchItemChanged() { mainContainer.updateNotch() }
                        function onNotchXChanged() { mainContainer.updateNotch() }
                    }
                    property real reveal: notchOn ? 1 : 0
                    Behavior on reveal {
                        NumberAnimation {
                            duration: mainContainer.notchOn ? 160 : 120
                            easing.type: mainContainer.notchOn ? Easing.OutCubic : Easing.InCubic
                        }
                    }

                    // Píldora (radio = alto/2, inset 0.5px para que el trazo quede
                    // dentro) con la muesca en el borde inferior
                    Shape {
                        id: barShape
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        readonly property real r: (height - 1) / 2
                        readonly property real hw: mainContainer.notchHalfWidth * mainContainer.reveal
                        readonly property real depth: mainContainer.notchDepth * mainContainer.reveal
                        readonly property real c: Math.max(r + hw, Math.min(width - r - hw, mainContainer.notchCenter))
                        readonly property real yb: height - 0.5

                        ShapePath {
                            // Extraer colores de Singleton
                            fillGradient: LinearGradient {
                                x1: 0; y1: 0; x2: barShape.width; y2: 0
                                GradientStop { position: 0.0; color: Qt.alpha(Colors.palette[0], 0.35) }
                                GradientStop { position: 0.5; color: Qt.alpha(Colors.palette[5], 0.35) }
                                GradientStop { position: 1.0; color: Qt.alpha(Colors.palette[0], 0.35) }
                            }
                            strokeColor: Qt.alpha(Colors.palette[7], 0.5)
                            strokeWidth: 1

                            startX: 0.5 + barShape.r; startY: 0.5
                            PathLine { x: barShape.width - 0.5 - barShape.r; y: 0.5 }
                            PathArc {
                                x: barShape.width - 0.5 - barShape.r; y: barShape.yb
                                radiusX: barShape.r; radiusY: barShape.r
                                direction: PathArc.Clockwise
                            }
                            PathLine { x: barShape.c + barShape.hw; y: barShape.yb }
                            PathCubic {
                                x: barShape.c; y: barShape.yb - barShape.depth
                                control1X: barShape.c + 4.25 * mainContainer.reveal; control1Y: barShape.yb
                                control2X: barShape.c + 2 * mainContainer.reveal; control2Y: barShape.yb - barShape.depth
                            }
                            PathCubic {
                                x: barShape.c - barShape.hw; y: barShape.yb
                                control1X: barShape.c - 2 * mainContainer.reveal; control1Y: barShape.yb - barShape.depth
                                control2X: barShape.c - 4.25 * mainContainer.reveal; control2Y: barShape.yb
                            }
                            PathLine { x: 0.5 + barShape.r; y: barShape.yb }
                            PathArc {
                                x: 0.5 + barShape.r; y: 0.5
                                radiusX: barShape.r; radiusY: barShape.r
                                direction: PathArc.Clockwise
                            }
                        }
                    }

                    // Animación en los huecos entre secciones (debajo de ellas)
                    BarStream {
                        anchors.fill: parent
                        readonly property real pad: 10
                        gaps: [
                            { x1: leftside.x + leftside.width + pad, x2: midside.x - pad },
                            { x1: midside.x + midside.width + pad, x2: rightside.x - pad }
                        ]
                    }

                    // Rectangulo izquierdo
                    LeftSide { id: leftside; radius: 10; barHeight: root.height }

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
                    panelColor: [SpotifyInfo.albumBg, SpotifyInfo.albumBgDeep]
                    offsetX: -70 // hacia el centro de la barra; ajustar a gusto
                    panelWidth: 500

                    Loader {
                        anchors.fill: parent
                        active: spotifyPopup.contentActive
                        sourceComponent: Component {
                            SpotifyAll {
                                anchors.fill: parent
                                accent: SpotifyInfo.albumAccent
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
