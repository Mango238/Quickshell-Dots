import QtQuick
import qs.Services
import qs.Commons

Rectangle {
    id: btn

    property string label: "󰺣"
    property bool danger: false

    signal clicked()

    implicitWidth: labelText.implicitWidth + 20
    implicitHeight: 20
    radius: 13
    color: {
        const base = PopupState.isOpen("equalizer") ? Colors.accent
                                                   : Qt.alpha(Colors.accent, 0.45)
        return mouseArea.pressed ? Qt.darker(base, 1.25) : base
    }
    scale: mouseArea.pressed ? 0.96 : 1.0

    Behavior on color { ColorAnimation { duration: 80 } }
    Behavior on scale { NumberAnimation { duration: 80 } }

    Text {
        id: labelText
        anchors.centerIn: parent
        text: btn.label
        font.pixelSize: 15
        font.bold: true
        color: "#1E1E2E"
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: {
            PopupState.toggle("equalizer")
        }
    }
}

