import QtQuick
/**
 * BluetoothActionButton.qml — Pastilla de acción compacta ("Conectar",
 * "Emparejar", "Desconectar", "Cancelar") usada por BluetoothDeviceRow.
 */
Rectangle {
    id: btn

    property string label: "󰂯"
    property bool danger: false
    property color accentColor: "#89B4FA"
    property color dangerColor: "#F38BA8"

    signal clicked()

    implicitWidth: labelText.implicitWidth + 20
    implicitHeight: 20
    radius: 13
    color: {
        var base = danger ? dangerColor : accentColor
        return mouseArea.pressed ? Qt.darker(base, 1.25) : base
    }

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
            btn.clicked()
        }
    }
}
