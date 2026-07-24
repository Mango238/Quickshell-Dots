import Quickshell
import QtQuick
import qs.Commons
import qs.Services
import qs.Widgets.Equalizer

PanelWindow {
    implicitWidth: 560
    implicitHeight: 440
    color: "transparent"
    visible: PopupState.isOpen("equalizer")

    Rectangle {
        anchors.fill: parent
        radius: 17
        color: Qt.alpha(Colors.ready ? Colors.palette[0] : "#1E1E2E", 0.94)
        border.width: 1
        border.color: Qt.alpha(Colors.accent, 0.35)

        EqualizerBackend { id: backend }

        EqControlsCard {
            anchors.fill: parent
            anchors.margins: 18
            backend: backend
        }
    }
}
