import QtQuick
import QtQuick.Shapes
import qs.Commons

/**
 * Un cable entre dos tarjetas. Es un Shape declarativo, no un Canvas: los extremos son
 * bindings a la x/y de las tarjetas, así que arrastrar un nodo redibuja el cable sin
 * ningún timer de repintado.
 *
 * El grosor y el brillo siguen el pico del nodo origen, así que el cable late con el
 * audio que realmente lo cruza.
 *
 * Los puntos de control son horizontales y simétricos, así que el punto medio de la
 * bézier cae justo en el punto medio de los extremos — ahí va la ✕ de desconectar.
 */
Item {
    id: cable

    required property var linkGroup
    required property Item graph

    anchors.fill: parent

    readonly property var srcCard: graph.cardOf(linkGroup.source ? linkGroup.source.id : -1)
    readonly property var dstCard: graph.cardOf(linkGroup.target ? linkGroup.target.id : -1)
    // Un nodo puede desaparecer (auricular bluetooth) antes de que se vaya su link group.
    readonly property bool valid: srcCard !== null && dstCard !== null

    readonly property real ax: valid ? srcCard.x + srcCard.width : 0
    readonly property real ay: valid ? srcCard.y + srcCard.height / 2 : 0
    readonly property real bx: valid ? dstCard.x : 0
    readonly property real by: valid ? dstCard.y + dstCard.height / 2 : 0
    readonly property real bend: Math.max(45, Math.abs(bx - ax) * 0.45)
    readonly property real level: valid ? Math.min(1, srcCard.level) : 0

    visible: valid

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        // Halo: ancho y translúcido, se abre con el nivel.
        ShapePath {
            strokeColor: Qt.alpha(Colors.accent, 0.10 + cable.level * 0.30)
            strokeWidth: 9 + cable.level * 10
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: cable.ax
            startY: cable.ay
            PathCubic {
                x: cable.bx; y: cable.by
                control1X: cable.ax + cable.bend; control1Y: cable.ay
                control2X: cable.bx - cable.bend; control2Y: cable.by
            }
        }

        // Núcleo.
        ShapePath {
            strokeColor: hover.hovered ? Colors.danger
                                       : Qt.alpha(Colors.accent, 0.55 + cable.level * 0.45)
            strokeWidth: 1.8 + cable.level * 2.2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: cable.ax
            startY: cable.ay
            PathCubic {
                x: cable.bx; y: cable.by
                control1X: cable.ax + cable.bend; control1Y: cable.ay
                control2X: cable.bx - cable.bend; control2Y: cable.by
            }
        }
    }

    // Desconectar: hit-test sobre el punto medio en vez de resolver "click sobre bézier".
    Rectangle {
        width: 18
        height: 18
        radius: 9
        x: (cable.ax + cable.bx) / 2 - width / 2
        y: (cable.ay + cable.by) / 2 - height / 2
        color: hover.hovered ? Colors.danger : Qt.alpha(Colors.palette[0], 0.85)
        border.width: 1
        border.color: hover.hovered ? Colors.danger : Qt.alpha(Colors.accent, 0.4)
        opacity: hover.hovered ? 1.0 : 0.35

        Behavior on opacity { NumberAnimation { duration: Config.anim.instant } }

        Text {
            anchors.centerIn: parent
            text: "✕"
            font.pixelSize: 10
            color: hover.hovered ? Colors.accentText : Qt.alpha(Colors.accent, 0.8)
        }

        HoverHandler { id: hover }

        TapHandler {
            onTapped: cable.graph.disconnectGroup(cable.linkGroup)
        }
    }
}
