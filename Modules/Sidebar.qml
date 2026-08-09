pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Services
import qs.Commons
import qs.Widgets.Sidebar

// Barra lateral overlay anclada al borde izquierdo. Una PanelWindow por
// monitor (como Bar.qml); solo la del monitor donde se abrió se hace visible
// (SidebarState.isOpenOn). El panel entra deslizándose desde la izquierda y se
// cierra al hacer click fuera (HyprlandFocusGrab) o con Escape. El contenido
// (rail + vista activa) se instancia perezoso al abrir.
Scope {
    id: scope

    Variants {
        model: Quickshell.screens
        delegate: Component {
            PanelWindow {
                id: win
                required property var modelData
                screen: modelData
                color: "transparent"
                exclusiveZone: 1

                // Usa modelData (el QScreen estable de Variants), NO win.screen:
                // win.screen fluctúa al mapear/desmapear la ventana según su
                // visibilidad, y como `visible` depende de `open`, leer
                // win.screen aquí crea el ciclo open → visible → screen → open.
                readonly property bool open: SidebarState.open && SidebarState.isOpenOn(win.modelData)

                Component.onCompleted: {
                    if (win.WlrLayershell != null) {
                        win.WlrLayershell.layer = WlrLayer.Top
                        win.WlrLayershell.namespace = "qs-sidebar"
                        // OnDemand: la ventana acepta teclado cuando tiene el
                        // grab (buscador de notas, input de chat), sin robar el
                        // foco de forma exclusiva al resto del sistema.
                        win.WlrLayershell.keyboardFocus = WlrKeyboardFocus.OnDemand
                    }
                }

                anchors { top: true; bottom: true; left: true }
                // Editar una nota en 440px es incómodo: el panel se ensancha
                // mientras el editor está abierto.
                implicitWidth: (SidebarState.activeView === "obsidian" && ObsidianEditor.path !== "") ? 720 : 440
                Behavior on implicitWidth {
                    NumberAnimation { duration: Config.anim.base; easing.type: Config.easingOf(Config.anim.standard) }
                }
                margins { top: 6; bottom: 6; left: 6 }

                visible: win.open || slideAnim.running

                // Grab imperativo diferido: el setter C++ escribe active=false
                // cuando el compositor limpia el grab; Qt.callLater da un tick
                // para que la ventana se muestre antes de pedirlo (mismo patrón
                // que PanelPopup.qml).
                // Autoguardado: al cerrar el sidebar el Loader destruye la
                // vista, así que la nota se escribe acá. save() es no-op si no
                // hay cambios, da igual que se dispare una vez por monitor.
                onOpenChanged: {
                    if (!win.open)
                        ObsidianEditor.save()
                    Qt.callLater(() => grab.active = win.open)
                }

                HyprlandFocusGrab {
                    id: grab
                    windows: [ win ]
                    onCleared: if (win.open) SidebarState.close()
                }

                Rectangle {
                    id: panel
                    width: parent.width
                    height: parent.height
                    // -win.implicitWidth y no -width: `width` viene de parent.width,
                    // que a su vez mide la geometría de los hijos → ciclo. El ancho
                    // declarado de la ventana es el mismo número, sin la dependencia.
                    x: win.open ? 0 : -win.implicitWidth
                    radius: 18
                    color: Qt.alpha(Colors.palette[1], 0.2)
                    border.width: 1
                    border.color: Qt.alpha(Colors.palette[7], 0.4)

                    Behavior on x {
                        NumberAnimation { id: slideAnim; duration: Config.anim.base; easing.type: Config.easingOf(Config.anim.standard) }
                    }

                    focus: true
                    Keys.onEscapePressed: SidebarState.close()

                    // Rail de vistas. Item (no Column) porque el botón marcado
                    // `bottom` se ancla al borde inferior en vez de apilarse.
                    Item {
                        id: rail
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: 62

                        Repeater {
                            model: [
                                { key: "obsidian", glyph: "󰠮", bottom: false },
                                { key: "claude",   glyph: "󰚩", bottom: false },
                                { key: "instagram", glyph: "󰋾", bottom: false },
                                { key: "config",   glyph: "󰒓", bottom: true  },
                            ]
                            delegate: Rectangle {
                                id: railBtn
                                required property var modelData
                                required property int index
                                readonly property bool active: SidebarState.activeView === modelData.key
                                x: 10
                                y: modelData.bottom ? rail.height - height - 14 : 14 + index * 52
                                width: 42
                                height: 42
                                radius: 12
                                color: active ? Colors.accent
                                     : railHover.containsMouse ? Qt.alpha(Colors.palette[4], 0.6)
                                     : Qt.alpha(Colors.palette[3], 0.4)
                                Behavior on color { ColorAnimation { duration: Config.anim.instant } }

                                Text {
                                    anchors.centerIn: parent
                                    text: railBtn.modelData.glyph
                                    font.pixelSize: 22
                                    color: railBtn.active ? Colors.accentText : "#e6e6e6"
                                }
                                MouseArea {
                                    id: railHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: SidebarState.activeView = railBtn.modelData.key
                                }
                            }
                        }
                    }

                    // Separador rail | contenido
                    Rectangle {
                        id: divider
                        anchors { left: rail.right; top: parent.top; bottom: parent.bottom
                                  topMargin: 14; bottomMargin: 14 }
                        width: 1
                        color: Qt.alpha(Colors.palette[7], 0.45)
                    }

                    // Contenido de la vista activa (lazy)
                    Loader {
                        id: content
                        anchors { left: divider.right; top: parent.top; right: parent.right; bottom: parent.bottom
                                  margins: 16 }
                        active: win.open
                        sourceComponent: SidebarState.activeView === "claude" ? claudeComp
                                       : SidebarState.activeView === "instagram" ? instagramComp
                                       : SidebarState.activeView === "config" ? settingsComp
                                       : ObsidianEditor.path !== "" ? noteEditorComp
                                       : obsidianComp
                    }

                    Component { id: obsidianComp; ObsidianView { anchors.fill: parent } }
                    Component { id: noteEditorComp; NoteEditor { anchors.fill: parent } }
                    Component { id: claudeComp;   ClaudeCodeView { anchors.fill: parent } }
                    Component { id: instagramComp; InstagramView { anchors.fill: parent } }
                    Component { id: settingsComp; SettingsView { anchors.fill: parent } }
                }
            }
        }
    }
}
