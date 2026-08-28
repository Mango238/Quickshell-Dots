import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Services
import qs.Widgets.Equalizer

PanelWindow {
    id: win

    implicitWidth: 560
    implicitHeight: 440
    color: "transparent"
    visible: PopupState.isOpen("equalizer")

    // OnDemand + el grab de abajo: sin foco de teclado del compositor, un
    // Keys.onEscapePressed en el contenido seria codigo muerto — la layer surface
    // nunca recibiria la tecla.
    Component.onCompleted: {
        if (win.WlrLayershell != null)
            win.WlrLayershell.keyboardFocus = WlrKeyboardFocus.OnDemand
    }

    // Asignacion imperativa diferida: el setter C++ del grab escribe active=false
    // cuando el compositor lo limpia, lo que destruiria un binding declarativo.
    // Mismo patron que PanelPopup.qml y Sidebar.qml.
    onVisibleChanged: Qt.callLater(() => grab.active = win.visible)

    HyprlandFocusGrab {
        id: grab
        windows: [ win ]
        onCleared: if (win.visible) PopupState.close()
    }

    Rectangle {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: PopupState.close()
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
