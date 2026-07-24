import QtQuick
import Quickshell.Widgets
import qs.Commons
import qs.Services

// Widget de estado de red: icono WiFi (señal/apagado, vía WifiService) +
// velocidad down/up (singleton NetworkStats). Clic → popup "wifi" con la
// lista de redes (WifiNetworkList). Vive dentro de un BarPill, cuyo hover
// usa HoverHandler y no roba los clics de este MouseArea.
WrapperItem {
    Item {
        implicitWidth: content.width
        implicitHeight: content.height

        Row {
            id: content
            spacing: 6

            Text {
                text: WifiService.statusIcon
                color: !WifiService.enabled
                    ? Colors.danger
                    : (WifiService.connected ? Colors.accent
                                             : Qt.alpha(Colors.ensureReadable(Colors.palette[7], Colors.palette[4]), 0.6))
                font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "󰬦 " + NetworkStats.downloadSpeed + " |" + " 󰬬 " + NetworkStats.uploadSpeed
                color: Colors.ensureReadable(Colors.palette[7], Colors.palette[4])
                font.pixelSize: 12
                font.family: "Monospace"
                horizontalAlignment: Text.AlignLeft
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: PopupState.toggle("wifi")
        }
    }
}
