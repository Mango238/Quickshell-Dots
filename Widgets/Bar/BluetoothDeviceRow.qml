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

    // Un dispositivo NO confiado hace que bluetoothd rechace la autorización de sus
    // perfiles al conectar ("Authentication attempt without agent" +
    // "a2dp.c:auth_cb() Access denied" en journalctl -u bluetooth): sin un agente BlueZ
    // registrado en el sistema no hay quién autorice, y BlueZ solo salta ese paso cuando
    // el device está Trusted. Por eso todo camino que termina en connect() lo marca antes
    // — es el equivalente al `bluetoothctl trust` que se hace a mano.
    property bool requesting: false

    function connectTrusted(pairFirst) {
        if (!row.device) return
        row.device.trusted = true
        if (pairFirst) {
            row.device.pair()   // el resto lo encadena onPairedChanged
            return
        }
        row.requesting = true
        requestTimeout.restart()
        row.device.connect()
    }

    Connections {
        target: row.device

        // pair() deja el device emparejado pero desconectado: sin esto el usuario tiene
        // que hacer un segundo clic en "Conectar" para que suene.
        function onPairedChanged() {
            if (row.device.paired) row.connectTrusted(false)
        }

        function onConnectedChanged() {
            row.requesting = false
            requestTimeout.stop()
        }
    }

    // Si la conexión falla no llega ningún connectedChanged y el botón quedaba en
    // "Conectando..." para siempre.
    Timer {
        id: requestTimeout
        interval: 8000
        onTriggered: row.requesting = false
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
                label: "Emparejar"
                onClicked: row.connectTrusted(true)
                accentColor: row.accentColor
                dangerColor: row.dangerColor
            }

            BluetoothActionButton {
                id: connectBtn
                visible: !row.isPairing && row.isPaired && !row.isConnected

                label: row.requesting ? "Conectando..." : "Conectar"
                onClicked: row.connectTrusted(false)
                accentColor: row.accentColor
                dangerColor: row.dangerColor
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
