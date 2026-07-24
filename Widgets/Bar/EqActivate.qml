import QtQuick
import qs.Services

Rectangle {
    id: btn

    property string label: "󰺣"
    property bool danger: false
    property color accentColor: "#ffffff"

    signal clicked()

    implicitWidth: labelText.implicitWidth + 20
    implicitHeight: 20
    radius: 13
    color: accentColor

    Behavior on color { ColorAnimation { duration: 80 } }

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

