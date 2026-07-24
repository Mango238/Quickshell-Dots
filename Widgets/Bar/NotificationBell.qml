import QtQuick
import qs.Services
import qs.Commons

/**
 * NotificationBell.qml — Campana de notificaciones para la píldora de
 * RightSide, con badge de no-leídas. Mismo patrón que Spoti.qml/PowerOff.qml:
 * solo contenido, el chrome de píldora lo pone el Repeater de RightSide.
 */
Item {
    id: root

    implicitWidth: bellText.implicitWidth
    implicitHeight: 20

    Text {
        id: bellText
        anchors.centerIn: parent
        text: NotificationService.dndEnabled ? "󰂛" : "󰂚"
        color: Colors.ensureReadable(Colors.palette[7], Colors.palette[4])
        font.pixelSize: 15
    }

    Rectangle {
        id: badge
        visible: NotificationService.unreadCount > 0
        width: Math.max(14, badgeText.implicitWidth + 6)
        height: 14
        radius: 7
        color: NotificationService.dndEnabled ? Qt.alpha(Colors.danger, 0.45) : Colors.danger
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: -4
        anchors.rightMargin: -6

        Text {
            id: badgeText
            anchors.centerIn: parent
            text: NotificationService.unreadCount > 9 ? "9+" : String(NotificationService.unreadCount)
            color: Colors.accentText
            font.pixelSize: 9
            font.bold: true
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                NotificationService.toggleDnd()
            } else {
                PopupState.toggle("notifications")
            }
        }
    }
}
