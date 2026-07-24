pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Services

/**
 * WifiNetworkList.qml — Selector de redes WiFi (clon estructural de
 * BluetoothDeviceList, con backend nativo Quickshell.Networking vía
 * WifiService). Pensado para insertarse como `content` de un PanelPopup
 * con grabKeyboardFocus (el campo de contraseña necesita teclado real).
 */
Item {
    id: root

    property color textColor: "#FFFFFF"
    property color subTextColor: "#B0B0C0"
    property color rowColor: "#2A2A3A"
    property color rowHoverColor: "#35354A"
    property color accentColor: "#89B4FA"
    property color dangerColor: "#F38BA8"
    property color dividerColor: "#3A3A4E"
    property real rowRadius: 8

    readonly property bool deviceReady: WifiService.device !== null
    readonly property bool scanning: deviceReady && WifiService.device.scannerEnabled

    Column {
        anchors.fill: parent
        spacing: 10

        // ── Header: estado + escaneo + switch de radio ─────────────────────
        RowLayout {
            id: header
            width: parent.width
            spacing: 8

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: "WiFi"
                    color: root.textColor
                    font.pixelSize: 15
                    font.bold: true
                }

                Text {
                    visible: WifiService.connected
                    text: WifiService.ssid
                    color: root.accentColor
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            BusyIndicator {
                visible: root.scanning
                running: root.scanning
                implicitWidth: 16
                implicitHeight: 16
            }

            Rectangle {
                Layout.preferredWidth: scanLabel.implicitWidth + 20
                Layout.preferredHeight: 28
                radius: 14
                color: scanArea.pressed ? Qt.darker(root.accentColor, 1.2) : root.accentColor
                opacity: root.deviceReady && WifiService.enabled ? 1.0 : 0.4

                Text {
                    id: scanLabel
                    anchors.centerIn: parent
                    text: root.scanning ? "Escaneando…" : "Buscar"
                    color: "#1E1E2E"
                    font.pixelSize: 12
                    font.bold: true
                }

                MouseArea {
                    id: scanArea
                    anchors.fill: parent
                    enabled: root.deviceReady && WifiService.enabled
                    onClicked: WifiService.device.scannerEnabled = !WifiService.device.scannerEnabled
                }
            }

            // Switch de encendido del radio WiFi
            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 24
                radius: 12
                color: WifiService.enabled ? root.accentColor : root.dividerColor

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    color: "#FFFFFF"
                    y: 3
                    x: WifiService.enabled ? parent.width - width - 3 : 3
                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: WifiService.setEnabled(!WifiService.enabled)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: root.dividerColor
        }

        // ── Estados vacíos ─────────────────────────────────────────────────
        Text {
            visible: !root.deviceReady
            width: parent.width
            wrapMode: Text.WordWrap
            text: "No se encontró ningún dispositivo WiFi."
            color: root.subTextColor
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            visible: root.deviceReady && !WifiService.enabled
            width: parent.width
            wrapMode: Text.WordWrap
            text: "WiFi apagado."
            color: root.subTextColor
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            visible: root.deviceReady && WifiService.enabled && WifiService.networks.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.scanning
                ? "Buscando redes cercanas…"
                : "No hay redes visibles. Toca \"Buscar\" para escanear."
            color: root.subTextColor
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
        }

        // ── Lista de redes ─────────────────────────────────────────────────
        ListView {
            id: networkListView
            width: parent.width
            height: parent.height - header.height - 24
            clip: true
            spacing: 6

            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            opacity: root.deviceReady && WifiService.enabled ? 1 : 0
            visible: opacity ? true : false

            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            // Array JS ya ordenado (activa primero, luego por señal) — a
            // diferencia de bluetooth (ObjectModel directo), acá el orden
            // lo da WifiService.networks y modelData llega como var.
            model: WifiService.networks

            delegate: WifiNetworkRow {
                required property var modelData
                width: networkListView.width
                network: modelData
                rowColor: root.rowColor
                rowHoverColor: root.rowHoverColor
                textColor: root.textColor
                subTextColor: root.subTextColor
                accentColor: root.accentColor
                dangerColor: root.dangerColor
                radius: root.rowRadius
            }
        }
    }
}
