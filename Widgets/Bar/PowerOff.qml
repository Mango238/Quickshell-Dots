import Qt5Compat.GraphicalEffects
import QtQuick
import qs.Commons
import qs.Services
Rectangle {
    id: main
    color: "transparent"
    clip: false

    width: powerIcon.contentWidth

    Glow {
        id: glow
        anchors.fill: powerIcon
        source: powerIcon
        color: "red"
        spread: 0.8
        // Radio reescalado junto al icono (25px→16px) para que el glow siga
        // proporcionado y no se desborde de la píldora de 20px.
        radius: 20
        samples: 41             // 1 + radius * 2, fijo (no animar: recompila shaders)
        visible: opacity > 0

        property bool active: false
        opacity: active ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
    }
    Text {
        clip: false
        id: powerIcon
        text: "⏻"
        color: Colors.ensureReadable(Colors.palette[7], Colors.palette[4])
        // Bajado de 25 a 16 para que quepa sin desbordar la píldora de 20px.
        font.pixelSize: 16
        // Centramos el icono horizontalmente respecto a los botones
        horizontalAlignment: Text.AlignHCenter
        anchors.centerIn: parent
        width: parent.width 
        
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: PopupState.toggle("power")
            hoverEnabled: true

            onEntered: glow.active = true
            onExited: glow.active = false
        }
    }
}
