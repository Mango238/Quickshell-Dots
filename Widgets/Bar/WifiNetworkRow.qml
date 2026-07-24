import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs.Services

/**
 * WifiNetworkRow.qml — Fila individual dentro de WifiNetworkList.
 *
 * Estados de una WifiNetwork y su mapeo a UI (espejo de BluetoothDeviceRow):
 *   - stateChanging == true            → "Conectando…" (botones ocultos)
 *   - connected == true                → botón "Desconectar"
 *   - known || security == Open        → botón "Conectar" (connect())
 *   - !known && security != Open       → botón "Conectar" expande un campo
 *                                        de contraseña; Enter → connectWithPsk()
 *   - known                            → "✕" para olvidar el perfil
 * El signal connectionFailed marca error (contraseña incorrecta, timeout).
 */
Item {
    id: row

    // Objeto WifiNetwork del módulo nativo; llega como var desde el model
    // (array JS ya ordenado por WifiService, no un ObjectModel).
    required property var network

    property color rowColor: "#2A2A3A"
    property color rowHoverColor: "#35354A"
    property color textColor: "#FFFFFF"
    property color subTextColor: "#B0B0C0"
    property color accentColor: "#89B4FA"
    property color dangerColor: "#F38BA8"
    property real radius: 8

    property bool expanded: false
    property string errorText: ""

    readonly property bool isConnected: network && network.connected
    readonly property bool isKnown: network && network.known
    readonly property bool isOpen: network && network.security === WifiSecurityType.Open
    readonly property bool busy: network && network.stateChanging

    height: expanded ? 92 : 56
    Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    function _startPasswordConnect() {
        row.errorText = ""
        row.network.connectWithPsk(pskInput.text)
        row.expanded = false
    }

    Connections {
        target: row.network
        function onConnectionFailed() {
            row.errorText = "No se pudo conectar (¿contraseña incorrecta?)"
            // Reabrir el campo si la red requiere clave y no quedó guardada
            if (!row.isOpen && !row.isKnown) row.expanded = true
        }
        function onConnectedChanged() {
            if (row.network.connected) {
                row.errorText = ""
                row.expanded = false
            }
        }
    }

    Rectangle {
        id: bg
        anchors.fill: parent
        radius: row.radius
        color: hoverArea.containsMouse ? row.rowHoverColor : row.rowColor

        Behavior on color { ColorAnimation { duration: 100 } }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                spacing: 10

                // ── Señal + candado ──────────────────────────────────────
                Text {
                    text: WifiService.signalIcon(row.network ? row.network.signalStrength : 0)
                        + (row.isOpen ? "" : " 󰌾")
                    color: row.isConnected ? row.accentColor : row.subTextColor
                    font.pixelSize: 14
                }

                // ── SSID + estado ────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: row.network ? row.network.name : ""
                        color: row.textColor
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: {
                            if (row.errorText !== "") return row.errorText
                            if (row.busy) return "Conectando…"
                            var pct = row.network
                                ? WifiService.signalPercent(row.network.signalStrength) + "%"
                                : ""
                            if (row.isConnected) return "Conectada · " + pct
                            if (row.isKnown) return "Guardada · " + pct
                            return pct + (row.isOpen ? " · Abierta" : "")
                        }
                        color: row.errorText !== ""
                            ? row.dangerColor
                            : (row.isConnected ? row.accentColor : row.subTextColor)
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                // ── Acciones (mutuamente excluyentes) ────────────────────
                BluetoothActionButton {
                    visible: !row.busy && !row.isConnected && (row.isKnown || row.isOpen)
                    label: "Conectar"
                    onClicked: {
                        row.errorText = ""
                        row.network.connect()
                    }
                    accentColor: row.accentColor
                    dangerColor: row.dangerColor
                }

                BluetoothActionButton {
                    visible: !row.busy && !row.isConnected && !row.isKnown && !row.isOpen
                    label: row.expanded ? "Cancelar" : "Conectar"
                    danger: row.expanded
                    onClicked: {
                        row.expanded = !row.expanded
                        if (row.expanded) {
                            row.errorText = ""
                            pskInput.text = ""
                            // Diferido: el foco Wayland real lo da el grab
                            // del popup; forzar en el mismo tick puede no
                            // prender (patrón de DirectorySearchBar).
                            Qt.callLater(() => pskInput.forceActiveFocus())
                        }
                    }
                    accentColor: row.accentColor
                    dangerColor: row.dangerColor
                }

                BluetoothActionButton {
                    visible: !row.busy && row.isConnected
                    label: "Desconectar"
                    danger: true
                    onClicked: row.network.disconnect()
                    accentColor: row.accentColor
                    dangerColor: row.dangerColor
                }

                // ── Olvidar (solo perfiles guardados) ────────────────────
                Text {
                    visible: !row.busy && row.isKnown
                    text: "✕"
                    color: row.subTextColor
                    font.pixelSize: 14

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: row.network.forget()
                    }
                }
            }

            // ── Campo de contraseña (expandible) ─────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                Layout.bottomMargin: 8
                visible: row.expanded
                radius: 6
                color: Qt.darker(row.rowColor, 1.25)
                border.width: pskInput.activeFocus ? 2 : 1
                border.color: pskInput.activeFocus ? row.accentColor : Qt.rgba(1, 1, 1, 0.12)

                TextInput {
                    id: pskInput
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 40
                    verticalAlignment: TextInput.AlignVCenter
                    color: row.textColor
                    font.pixelSize: 12
                    echoMode: TextInput.Password
                    clip: true

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            row._startPasswordConnect()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            row.expanded = false
                            event.accepted = true
                        }
                    }
                }

                Text {
                    visible: pskInput.text.length === 0 && !pskInput.activeFocus
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Contraseña…"
                    color: row.subTextColor
                    font.pixelSize: 12
                }

                Text {
                    text: "󰌑"
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: pskInput.text.length > 0 ? row.accentColor : row.subTextColor
                    font.pixelSize: 14

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: row._startPasswordConnect()
                    }
                }
            }
        }
    }
}
