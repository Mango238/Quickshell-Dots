import QtQuick
import qs.Commons

/**
 * Conector de una tarjeta. El de salida (isOutput) es el que se arrastra para crear un
 * link; el de entrada solo marca dónde aterrizan los cables. El arrastre se reporta en
 * coordenadas del grafo, que es donde se dibuja el cable elástico.
 */
Rectangle {
    id: pin

    required property Item graph
    required property Item card
    required property bool isOutput

    readonly property bool armed: pin.isOutput && pin.graph.linkingFrom === pin.card.node.id

    width: 11
    height: 11
    radius: 5.5
    color: area.containsMouse || armed ? Colors.accent : Qt.alpha(Colors.accent, 0.45)
    border.width: 1
    border.color: Colors.palette[0]
    scale: area.containsMouse || armed ? 1.3 : 1.0

    Behavior on scale { NumberAnimation { duration: Config.anim.instant } }
    Behavior on color { ColorAnimation { duration: Config.anim.instant } }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.margins: -7
        hoverEnabled: true
        enabled: pin.isOutput
        cursorShape: pin.isOutput ? Qt.CrossCursor : Qt.ArrowCursor
        preventStealing: true

        function report(mouse) {
            const p = mapToItem(pin.graph, mouse.x, mouse.y)
            pin.graph.dragX = p.x
            pin.graph.dragY = p.y
        }

        onPressed: mouse => {
            report(mouse)
            pin.graph.linkingFrom = pin.card.node.id
        }
        onPositionChanged: mouse => report(mouse)
        onReleased: mouse => {
            const p = mapToItem(pin.graph, mouse.x, mouse.y)
            pin.graph.endLink(p.x, p.y)
        }
        onCanceled: pin.graph.linkingFrom = -1
    }
}
