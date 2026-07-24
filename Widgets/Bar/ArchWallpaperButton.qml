import QtQuick
import qs.Services
import qs.Commons

Rectangle {
    id: btn

    property string label: "󰣇"
    property bool danger: false
    property color accentColor: Colors.palette[2]
    property color dangerColor: Colors.danger

    signal clicked()

    implicitWidth: row.width +30
    implicitHeight: 20
    radius: 13
    color: {
        var base = danger ? dangerColor : accentColor
        return mouseArea.pressed ? Qt.darker(base, 1.25) : base
    }
    scale: mouseArea.pressed ? 0.96 : 1.0

    border.color: "#e6e6e6"

    Behavior on color { ColorAnimation { duration: 80 } }
    Behavior on scale { NumberAnimation { duration: 80 } }

    Row {
        id: row
        anchors.centerIn: parent
        Text {
            id: labelText
            text: btn.label
            font.pixelSize: 15
            color: Colors.ensureReadable("#e6e6e6", btn.accentColor)
        }

        AudioVisualization {
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 19
            visible: true
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onClicked: PopupState.toggle("wallpaper")
    }
}
