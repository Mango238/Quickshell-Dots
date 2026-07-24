import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth

/**
 * BluetoothDeviceRow.qml — Fila individual dentro de BluetoothDeviceList.
 *
 * Estados posibles de un BluetoothDevice y cómo los mapeamos a UI:
 *   - pairing == true            → "Emparejando…" (+ opción de cancelar)
 *   - paired == false            → botón "Emparejar" (pair())
 *   - paired == true, !connected → botón "Conectar" (connect())
 *   - connected == true          → botón "Desconectar" (disconnect())
 *   - siempre disponible         → "Olvidar" (forget()) si bonded/paired
 *
 * `connected` también se puede escribir directamente (según la doc,
 * equivale a llamar connect()/disconnect()), pero uso los métodos
 * explícitos para dejar la intención clara en el código.
 */
Item {
    id: row

    required property BluetoothDevice device

    property color rowColor: "#2A2A3A"
    property color rowHoverColor: "#35354A"
    property color textColor: "#FFFFFF"
    property color subTextColor: "#B0B0C0"
    property color accentColor: "#89B4FA"
    property color dangerColor: "#F38BA8"
    property real radius: 8

    height: 56

    readonly property bool isConnected: device && device.connected
    readonly property bool isPaired: device && device.paired
    readonly property bool isPairing: device && device.pairing

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

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 10
            spacing: 10

            // ── Icono del dispositivo ────────────────────────────────────
            Image {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                fillMode: Image.PreserveAspectFit
                source: row.device && row.device.icon
                    ? Quickshell.iconPath(row.device.icon, true)
                    : ""
                visible: source !== ""
            }

            // ── Nombre + estado ───────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: row.device ? row.device.name : ""
                    color: row.textColor
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (row.isPairing) return "Emparejando…"
                        if (row.isConnected && row.device.batteryAvailable)
                            return "Conectado · " + Math.round(row.device.battery * 100) + "%"
                        if (row.isConnected) return "Conectado"
                        if (row.isPaired) return "Emparejado"
                        return "Disponible"
                    }
                    color: row.isConnected ? row.accentColor : row.subTextColor
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            // ── Acción principal ──────────────────────────────────────────
            BluetoothActionButton {
                visible: row.isPairing
                label: "Cancelar"
                danger: true
                onClicked: row.device.cancelPair()
                accentColor: row.accentColor
                dangerColor: row.dangerColor
            }

            BluetoothActionButton {
                visible: !row.isPairing && !row.isPaired
                label: row.isPairing ? "Emparejando..." : "Emparejar" 
                onClicked: row.device.pair()
                accentColor: row.accentColor
                dangerColor: row.dangerColor
            }

            BluetoothActionButton {
                id: connectBtn
                visible: !row.isPairing && row.isPaired && !row.isConnected
                property bool requesting: false

                label: requesting ? "Conectando..." : "Conectar"
                onClicked: {
                    this.requesting = true
                    row.device.connect()
                }
                accentColor: row.accentColor
                dangerColor: row.dangerColor
                Connections {
                    target: row.device
                    function onConnectedChanged() { connectBtn.requesting = false }
                }
            }

            BluetoothActionButton {
                visible: !row.isPairing && row.isConnected
                label: "Desconectar"
                danger: true
                onClicked: row.device.disconnect()
                accentColor: row.accentColor
                dangerColor: row.dangerColor
            }

            // ── Olvidar (solo si ya está emparejado) ──────────────────────
            Text {
                visible: !row.isPairing && row.isPaired
                text: "✕"
                color: row.subTextColor
                font.pixelSize: 14

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: row.device.forget()
                }
            }
        }
    }
}
