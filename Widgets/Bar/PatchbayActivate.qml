import QtQuick
import qs.Services
import qs.Commons

// Botón suelto de la barra: abre/cierra el patchbay de PipeWire.
Rectangle {
    id: btn

    property string label: "󰡀"

    implicitWidth: labelText.implicitWidth + 20
    implicitHeight: 20
    radius: 13
    color: {
        const base = PopupState.isOpen("patchbay") ? Colors.accent
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
        color: Colors.ensureReadable(Colors.accentText, btn.color)
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: PopupState.toggle("patchbay")
    }
}
