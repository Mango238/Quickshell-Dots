import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import qs.Commons

WrapperMouseArea {

    cursorShape: Qt.PointingHandCursor
    onClicked: wayscriber.running = !wayscriber.running

    Process {
        id: wayscriber
        running: false
        command: [ "sh", "-c", "wayscriber --active" ]
    }

    Text {
        id: text
        text: "󱦹"
        color: Colors.ensureReadable(Colors.palette[7], Colors.palette[4])
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        font.pixelSize: 15
    }
}
