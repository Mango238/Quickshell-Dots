import QtQuick

/**
 * MediaButton.qml — Botón de icono para controles multimedia
 *
 * USO:
 *   MediaButton {
 *       text: "󰐊"                    // glyph Nerd Font
 *       baseColor: "#ffffff"
 *       activeColor: "#1db954"       // color cuando active = true
 *       active: player.shuffle       // estado resaltado (opcional)
 *       enabled: player.canGoNext
 *       onActivated: player.next()
 *   }
 */
Text {
    id: button

    signal activated()

    property bool active: false
    property color baseColor: "white"
    property color activeColor: baseColor

    color: active ? activeColor : baseColor
    opacity: enabled ? 1.0 : 0.35
    font.pixelSize: 18
    scale: mouse.containsMouse && enabled ? 1.15 : 1.0

    Behavior on scale { NumberAnimation { duration: 80 } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (button.enabled) button.activated()
    }
}
