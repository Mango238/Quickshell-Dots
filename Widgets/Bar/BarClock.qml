import QtQuick
import Quickshell
import qs.Commons

/**
 * BarClock.qml — Reloj compacto para la píldora de RightSide.
 *
 * Solo el contenido: el chrome de píldora (fondo, borde, radius, animación
 * de ancho) lo pone el Rectangle del Repeater en RightSide.qml, igual que
 * Spoti.qml / PowerOff.qml. Al crecer `row.width` en hover (mostrando la
 * fecha corta), el Behavior on width ya existente en ese Rectangle anima el
 * ensanche del pill gratis — no hace falta animar nada acá.
 *
 * Usa SystemClock con precision: Minutes (no un Timer de 1s) — no
 * necesitamos resolución de segundos y así evitamos actualizaciones/binding
 * evaluations innecesarias cada segundo.
 */
Item {
    id: root

    implicitWidth: row.width
    implicitHeight: 20

    property bool hovered: false

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
            id: timeText
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: Colors.ensureReadable(Colors.palette[7], Colors.palette[4])
            font.pixelSize: 12
            font.bold: true
        }

        Text {
            id: dateText
            anchors.verticalCenter: parent.verticalCenter
            visible: opacity > 0
            opacity: root.hovered ? 1.0 : 0.0
            text: Qt.formatDateTime(clock.date, "ddd d MMM")
            color: Colors.ensureReadable(Colors.palette[7], Colors.palette[4])
            font.pixelSize: 11

            Behavior on opacity {
                NumberAnimation { duration: 100 }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hovered = true
        onExited: root.hovered = false
    }
}
