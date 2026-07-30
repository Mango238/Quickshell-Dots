import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Services

/**
 * Tarjeta de un nodo de PipeWire dentro del patchbay.
 *
 * Se coloca sola (x/y vienen de PatchbayGraph al crearse) y el arrastre pisa esos
 * bindings a propósito: a partir del primer arrastre la tarjeta manda sobre el layout.
 *
 * El medidor de nivel usa PwNodePeakMonitor, que abre una captura de stream real. Por eso
 * `enabled` está acotado a "ventana abierta y nodo con al menos un link": encenderlo en
 * los nodos inertes es pagar capturas por nada.
 * ponytail: un monitor por nodo enlazado; si pesa, dejarlo solo en los nodos de la
 * cadena por defecto (Pipewire.defaultAudioSink y lo que cuelgue de él).
 */
Rectangle {
    id: card

    required property PwNode node
    required property Item graph
    // El nodo participa en algún link: sin esto no vale la pena abrirle un peak monitor.
    required property bool linked

    readonly property real level: peakMon.peak
    // `description`, `nickname` y `audio` de PwNode no tienen señal de notify: se llenan
    // cuando el PwObjectTracker termina de bindear el objeto, después de crearse esta
    // tarjeta. `ready` tampoco sirve de disparador (se queda en false aunque los datos
    // lleguen); la única que notifica es `properties`. Leerla aquí es lo que hace que
    // el resto se reevalúe en cuanto el bindeo aterriza.
    readonly property var props: node.properties || ({})
    readonly property string label: props["node.description"] || node.description
                                    || node.nickname || node.name
    readonly property var vol: props && node.audio ? node.audio : null
    readonly property var ports: PatchbayService.portsByNode[node.id] || null
    readonly property bool hasOut: ports !== null && ports.out.length > 0
    readonly property bool hasIn: ports !== null && ports.in.length > 0
    readonly property color fg: Colors.ensureReadable(Colors.palette[7], Colors.palette[4])

    width: 220
    height: 62
    radius: 8
    color: dragArea.drag.active ? Qt.lighter(Colors.palette[4], 1.2) : Colors.palette[4]
    border.width: 1
    border.color: Qt.alpha(Colors.accent, card.level > 0.01 ? 0.9 : 0.35)

    Accessible.role: Accessible.Grouping
    Accessible.name: title.text

    Behavior on color { ColorAnimation { duration: Config.anim.instant } }
    Behavior on border.color { ColorAnimation { duration: Config.anim.instant } }

    PwNodePeakMonitor {
        id: peakMon
        node: card.node
        enabled: card.graph.live && card.linked
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        drag.target: card
        drag.axis: Drag.XAndYAxis
    }

    WheelHandler {
        enabled: card.vol !== null
        onWheel: event => {
            const step = event.angleDelta.y > 0 ? 0.05 : -0.05
            card.vol.volume = Math.max(0, Math.min(1, card.vol.volume + step))
        }
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 9
        spacing: 3

        Text {
            id: title
            width: parent.width - 18
            elide: Text.ElideRight
            text: card.label
            font.family: Config.font
            font.pixelSize: 12
            color: card.fg
        }

        Text {
            width: parent.width - 18
            elide: Text.ElideRight
            text: card.props["media.class"] || ""
            font.family: Config.font
            font.pixelSize: 9
            color: Qt.alpha(card.fg, 0.55)
        }
    }

    // Mute: solo aparece en nodos con control de volumen.
    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        visible: card.vol !== null
        text: card.vol && card.vol.muted ? "󰝟" : "󰕾"
        font.pixelSize: 12
        color: card.vol && card.vol.muted ? Colors.danger : Qt.alpha(card.fg, 0.7)

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: card.vol.muted = !card.vol.muted
        }
    }

    // Medidor de nivel. Sube instantáneo y baja con caída suave, como un VU real:
    // un Behavior simétrico se come los picos y no se ve nada.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 6
        height: 3
        radius: 1.5
        color: Qt.alpha(Colors.palette[7], 0.15)

        Rectangle {
            id: meter
            height: parent.height
            radius: parent.radius
            width: parent.width * Math.min(1, card.level)
            color: Colors.accent
            Behavior on width {
                enabled: meter.width > parent.width * Math.min(1, card.level)
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }
    }

    PatchPin {
        id: inPin
        graph: card.graph
        card: card
        isOutput: false
        visible: card.hasIn
        anchors.horizontalCenter: parent.left
        anchors.verticalCenter: parent.verticalCenter
    }

    PatchPin {
        graph: card.graph
        card: card
        isOutput: true
        visible: card.hasOut
        anchors.horizontalCenter: parent.right
        anchors.verticalCenter: parent.verticalCenter
    }
}
