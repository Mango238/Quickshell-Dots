import Quickshell
import QtQuick
import qs.Commons
import qs.Services
import qs.Widgets.Patchbay

/**
 * Ventana del patchbay de PipeWire. Misma carcasa que Modules/Equalizer.qml, más grande
 * porque el grafo necesita sitio para tres columnas de tarjetas.
 *
 * El Loader evita instanciar el grafo — y sobre todo los peak monitors, que abren
 * capturas de stream reales — mientras la ventana está cerrada.
 */
PanelWindow {
    id: win

    implicitWidth: 1100
    implicitHeight: 700
    color: "transparent"
    visible: PopupState.isOpen("patchbay")

    onVisibleChanged: PatchbayService.active = win.visible

    Rectangle {
        anchors.fill: parent
        radius: 17
        color: Qt.alpha(Colors.ready ? Colors.palette[0] : "#1E1E2E", 0.94)
        border.width: 1
        border.color: Qt.alpha(Colors.accent, 0.35)

        Text {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 18
            text: "PipeWire"
            font.family: Config.font
            font.pixelSize: 15
            color: Colors.ensureReadable(Colors.palette[7], Colors.palette[0])
        }

        Text {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 18
            text: "arrastra desde el punto derecho de un nodo para conectar · ✕ sobre un cable para cortar · rueda para volumen · arrastra el fondo para mover el lienzo"
            font.family: Config.font
            font.pixelSize: 10
            color: Qt.alpha(Colors.palette[7], 0.45)
        }

        Loader {
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 14
            active: win.visible
            sourceComponent: Component {
                PatchbayGraph { live: win.visible }
            }
        }
    }
}
