pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth

/**
 * BluetoothDeviceList.qml — Selector de dispositivos Bluetooth
 *
 * Lista los dispositivos conocidos por el adaptador por defecto y permite
 * conectar / desconectar / emparejar / olvidar cada uno. Pensado para
 * insertarse como `content` dentro de un PanelPopup (ver Widgets/General).
 *
 * NOTA IMPORTANTE SOBRE LA API:
 * Este widget usa Quickshell.Bluetooth (wrapper QML sobre BlueZ vía DBus).
 * Verifiqué contra la documentación oficial las propiedades/métodos que
 * uso (Bluetooth.defaultAdapter, BluetoothAdapter.devices/discovering/
 * enabled, BluetoothDevice.connected/paired/pairing/bonded/battery/icon,
 * y los métodos connect()/disconnect()/pair()/forget()/cancelPair()).
 * Aun así, la propiedad `discovering` no está documentada explícitamente
 * como escribible (a diferencia de `enabled`, `discoverable` y
 * `pairable`, que sí lo son). Si en tu versión de Quickshell resulta ser
 * de solo lectura, verás un warning de "cannot assign to read-only
 * property" al tocar el botón de escaneo — en ese caso avisame y lo
 * cambiamos a los métodos equivalentes de inicio/detención de discovery.
 *
 * USO:
 *   PanelPopup {
 *       alignItem: bluetoothIcon
 *       show: BluetoothPanelState.open
 *       panelColor: Colors.palette[4]
 *       panelHeight: 320
 *
 *       BluetoothDeviceList {
 *           anchors.fill: parent
 *           anchors.margins: 12
 *       }
 *   }
 */
Item {
    id: root

    // ─── Apariencia (parametrizable, con defaults razonables) ──────────────

    property color textColor: "#FFFFFF"
    property color subTextColor: "#B0B0C0"
    property color rowColor: "#2A2A3A"
    property color rowHoverColor: "#35354A"
    property color accentColor: "#89B4FA"
    property color dangerColor: "#F38BA8"
    property color dividerColor: "#3A3A4E"
    property real rowRadius: 8

    // Adaptador activo. Se resuelve solo, pero se puede sobreescribir.
    property BluetoothAdapter adapter: Bluetooth.defaultAdapter

    readonly property bool adapterReady: adapter !== null
    readonly property bool scanning: adapterReady && adapter.discovering

    // ─── Layout raíz ────────────────────────────────────────────────────────

    Column {
        anchors.fill: parent
        spacing: 10

        // ── Header: estado del adaptador + botón de escaneo ────────────────
        RowLayout {
            id: header
            width: parent.width
            spacing: 8

            Text {
                text: "Bluetooth"
                color: root.textColor
                font.pixelSize: 15
                font.bold: true
                Layout.fillWidth: true
            }

            BusyIndicator {
                visible: root.scanning
                running: root.scanning
                implicitWidth: 16
                implicitHeight: 16
            }

            Rectangle {
                id: scanBtn
                Layout.preferredWidth: scanLabel.implicitWidth + 20
                Layout.preferredHeight: 28
                radius: 14
                color: scanArea.pressed ? Qt.darker(root.accentColor, 1.2) : root.accentColor
                opacity: root.adapterReady ? 1.0 : 0.4

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
                    enabled: root.adapterReady
                    onClicked: {
                        // Toggle de discovery. Ver NOTA de arriba si tu
                        // versión de Quickshell trata esto como read-only.
                        root.adapter.discovering = !root.adapter.discovering
                    }
                }
            }

            // Switch de encendido del adaptador
            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 24
                radius: 12
                color: (root.adapterReady && root.adapter.enabled) ? root.accentColor : root.dividerColor
                opacity: root.adapterReady ? 1.0 : 0.4

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    color: "#FFFFFF"
                    y: 3
                    x: (root.adapterReady && root.adapter.enabled) ? parent.width - width - 3 : 3
                    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.adapterReady
                    onClicked: root.adapter.enabled = !root.adapter.enabled
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: root.dividerColor
        }

        // ── Estado vacío / adaptador no disponible ─────────────────────────
        Text {
            visible: !root.adapterReady
            width: parent.width
            wrapMode: Text.WordWrap
            text: "No se encontró ningún adaptador Bluetooth."
            color: root.subTextColor
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            visible: root.adapterReady && root.adapter.devices.values.length === 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.scanning
                ? "Buscando dispositivos cercanos…"
                : "No hay dispositivos. Tocá \"Buscar\" para escanear."
            color: root.subTextColor
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
        }

        // ── Lista de dispositivos ───────────────────────────────────────────
        ListView {
            id: deviceListView
            width: parent.width
            height: parent.height - header.height - 24
            clip: true
            spacing: 6
            
            Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }


            opacity: root.adapterReady && root.adapter.enabled ? 1 : 0
            visible: opacity ? true : false

            model: root.adapterReady ? root.adapter.devices : null

            delegate: BluetoothDeviceRow {
                // adapter.devices es un Quickshell ObjectModel, no un array
                // JS plano: usarlo directo como "model" es correcto (así el
                // ListView refleja inserciones/remociones en vivo). Para leer
                // el ítem de cada fila usamos el rol "modelData" que expone
                // el propio ObjectModel: al declararlo acá como "required
                // property" queda ligado por el motor de delegados al ítem
                // de ESTE modelo específicamente (no hay shadowing posible
                // con un modelData de un ancestro, como el de un
                // Variants{ model: Quickshell.screens }, porque el binding
                // lo inyecta el ListView/DelegateModel más cercano, no la
                // resolución de scope de JS).
                //
                // OJO: el intento anterior de indexar a mano con
                // "root.adapter.devices.values[index]" y asignarlo a una
                // propiedad tipada (BluetoothDevice) es justamente lo que
                // generaba el warning "Unable to assign UntypedObjectModel
                // to qs::bluetooth::BluetoothDevice": adapter.devices se
                // expone en QML como UntypedObjectModel (tipo genérico), y
                // el motor no logra resolver el tipo concreto del elemento
                // indexado para la asignación. Usando el rol modelData ese
                // problema desaparece porque el valor llega ya tipado desde
                // el propio ObjectModel.
                required property BluetoothDevice modelData
                width: deviceListView.width
                device: modelData
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
