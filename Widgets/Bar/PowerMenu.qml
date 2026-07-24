pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import qs.Services

Item {
    id: menu

    // -1 = nada armado; N = índice de la acción esperando el click de confirmación
    property int armedIndex: -1

    readonly property var actions: [
        { icon: "󰌾", label: "Bloquear",      command: ["loginctl", "lock-session"] },
        { icon: "⏻", label: "Apagar",        command: ["systemctl", "poweroff"] },
        { icon: "󰜉", label: "Reiniciar",     command: ["systemctl", "reboot"] },
        { icon: "󰤄", label: "Suspender",     command: ["systemctl", "suspend"] },
        { icon: "󰍃", label: "Cerrar sesión", command: ["hyprctl", "dispatch", "exit"] }
    ]

    function disarm() {
        armedIndex = -1
        disarmTimer.stop()
    }

    Timer {
        id: disarmTimer
        interval: 4000
        onTriggered: menu.armedIndex = -1
    }

    Column {
        anchors.fill: parent
        spacing: 8

        Repeater {
            model: menu.actions

            delegate: Rectangle {
                id: actionRow
                required property var modelData
                required property int index
                readonly property bool armed: menu.armedIndex === index

                width: parent.width
                height: 40
                radius: 10
                color: armed ? Colors.danger
                             : rowMouse.containsMouse ? Qt.alpha(Colors.palette[6], 0.35)
                                                      : Qt.alpha(Colors.palette[5], 0.25)
                Behavior on color { ColorAnimation { duration: 100 } }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    spacing: 12

                    Text {
                        text: actionRow.modelData.icon
                        font.pixelSize: 16
                        color: actionRow.armed ? Colors.accentText : Colors.palette[7]
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: actionRow.armed ? "¿Seguro? Click de nuevo" : actionRow.modelData.label
                        font.pixelSize: 14
                        color: actionRow.armed ? Colors.accentText : Colors.palette[7]
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (menu.armedIndex === actionRow.index) {
                            // Capturar el comando antes de desarmar/cerrar
                            var cmd = menu.actions[actionRow.index].command
                            menu.disarm()
                            PopupState.toggle("power")
                            // execDetached y no un Process hijo: al cerrarse el
                            // popup, el Loader destruye este PowerMenu ~130 ms
                            // después (tras el fade) y un Process moriría con
                            // él, matando systemctl antes de llegar a logind
                            // (el botón "no hacía nada"). El proceso detached
                            // sobrevive a la destrucción del menú.
                            Quickshell.execDetached(cmd)
                        } else {
                            menu.armedIndex = actionRow.index
                            disarmTimer.restart()
                        }
                    }
                }
            }
        }
    }
}
