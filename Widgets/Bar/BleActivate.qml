import QtQuick
import qs.Services
import qs.Commons
/**
 * BluetoothActionButton.qml — Pastilla de acción compacta ("Conectar",
 * "Emparejar", "Desconectar", "Cancelar") usada por BluetoothDeviceRow.
 */
Rectangle {
    id: btn

    property string label: "󰂯"
    property bool danger: false
    property color accentColor: Colors.accent
    property color dangerColor: Colors.danger

    signal clicked()

    implicitWidth: labelText.implicitWidth + 20
    implicitHeight: 20
    radius: 13
    color: {
        var base = danger ? dangerColor : accentColor
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
        color: Colors.ensureReadable(Colors.accentText, btn.accentColor)
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            PopupState.toggle("bluetooth")
        }
    }
}
