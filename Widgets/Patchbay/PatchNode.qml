import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Services

/**
 * Tarjeta de un nodo de PipeWire dentro del patchbay.
 *
 * No se coloca sola: la posición vive en `graph.pos` y la tarjeta solo la lee al nacer
 * (x/y) y se la devuelve al soltar el arrastre. Tiene que ser así porque PipeWire destruye
 * y recrea este delegate cada vez que aparece o desaparece un nodo, y una posición guardada
 * en la tarjeta se perdía en cada una de esas.
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
    // Candidato a sink por defecto: nodos de dispositivo que aceptan audio — tarjetas,
    // auriculares y también el filter-chain del ecualizador (Source y Sink a la vez).
    // Los streams no, aunque lleven el bit Sink: ahí ese bit significa "reproduce"
    // (ver roleOf en PatchbayGraph), no "es una salida".
    readonly property bool canBeDefault: (node.type & PwNodeType.Sink) !== 0
                                         && (node.type & PwNodeType.Stream) === 0
    readonly property bool isDefault: Pipewire.defaultAudioSink === card.node
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
        // Sin esto el Flickable del grafo roba el grab pasado el umbral de arrastre: la
        // tarjeta se quedaría clavada y lo que se movería es el lienzo entero.
        preventStealing: true
        // El scroll está acotado en 0 (StopAtBounds), así que una tarjeta con coordenadas
        // negativas quedaba fuera de alcance para siempre. Único clamp que hace falta:
        // colX/rowY ya devuelven positivos, así que savePos nunca ve un negativo.
        drag.minimumX: 0
        drag.minimumY: 0
        // Al soltar (o al cancelarse el grab) hay que devolverle la posición al grafo: es
        // lo único que sobrevive a que PipeWire recree este delegate.
        drag.onActiveChanged: if (!dragArea.drag.active && card.node)
            card.graph.savePos(card.node.id, card.x, card.y)
    }

    // Marquesina del título: solo con el ratón sobre la tarjeta. HoverHandler y no
    // `hoverEnabled` en dragArea porque es pasivo — ni el MouseArea del mute ni el
    // preventStealing del arrastre lo tocan.
    HoverHandler { id: cardHover }

    // Mide el texto CRUDO. Con elide activo, el contentWidth del Text es el del texto ya
    // recortado, así que usarlo ataría la condición al mismo elide que la condición
    // controla. TextMetrics es inmune a eso y deja fijo el recorrido de la animación.
    TextMetrics {
        id: titleMetrics
        font: title.font
        text: card.label
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

        // Con el ratón encima se apaga el elide y el texto va y vuelve dentro del recorte;
        // sin hover queda exactamente como antes, elidido con "…" y quieto. Mismo
        // `parent.width - 18` de siempre para que ese estado sea idéntico píxel a píxel.
        Item {
            id: titleClip

            // Se descuenta la fila de iconos medida, no un 18 fijo: con la estrella puesta
            // son dos iconos y el título se metía debajo. `actions` no depende de esta
            // anchura (su tamaño sale de las métricas de sus textos), así que no hay loop.
            width: parent.width - actions.width - 5
            height: title.implicitHeight
            clip: true

            Text {
                id: title

                property real scrollOffset: 0

                width: parent.width
                wrapMode: Text.NoWrap
                elide: cardHover.hovered ? Text.ElideNone : Text.ElideRight
                x: -title.scrollOffset
                text: card.label
                font.family: Config.font
                font.pixelSize: 12
                color: card.fg

                // Ida y vuelta con pausa en cada punta, como la otra marquesina del repo
                // (Widgets/Bar/Spotify.qml), pero NO con sus tiempos: sus 60 ms/px están
                // calibrados para el desborde chico de la barra. Acá los nodos se llaman
                // "Core Ultra 200V Series Processors HD Audio HDMI / DisplayPort 1 Output"
                // — medido, 503 px contra 184 de ancho útil, o sea 324 px de recorrido, que
                // a 60 ms/px son 19 s por pasada. A 20 ms/px (50 px/s, velocidad de lectura
                // cómoda) son 6,5 s. La pausa inicial también baja: el hover es una acción
                // deliberada, esperar 2 s a que arranque lo que pediste se siente roto.
                SequentialAnimation {
                    id: marquee

                    readonly property real travel:
                        titleMetrics.advanceWidth - titleClip.width + 5
                    readonly property int dur: Math.max(1400, marquee.travel * 20)

                    running: cardHover.hovered && marquee.travel > 0
                    loops: Animation.Infinite
                    // Al salir el ratón vuelve a 0: si no, el próximo hover se pasa la pausa
                    // inicial mostrando el offset viejo antes de que la animación lo pise.
                    onRunningChanged: if (!marquee.running) title.scrollOffset = 0

                    PauseAnimation { duration: 100 }

                    NumberAnimation {
                        target: title
                        property: "scrollOffset"
                        from: 0
                        to: marquee.travel
                        duration: marquee.dur
                        easing.type: Easing.Linear
                    }

                    PauseAnimation { duration: 1200 }

                    NumberAnimation {
                        target: title
                        property: "scrollOffset"
                        to: 0
                        duration: marquee.dur
                        easing.type: Easing.Linear
                    }
                }
            }
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

    // Esquina de acciones: predeterminado y mute.
    Row {
        id: actions

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        spacing: 12

        // Estrella: marca este nodo como sink por defecto de PipeWire. Es lo mismo que
        // `wpctl set-default`, así que wireplumber manda ahí los streams nuevos y arrastra
        // los que ya suenan y no tengan un destino fijado a mano.
        // No hay estado "sin predeterminado" que desmarcar: PipeWire siempre tiene uno.
        Text {
            visible: card.canBeDefault
            text: card.isDefault ? "󰓎" : "󰓒"
            font.pixelSize: 12
            color: card.isDefault ? Colors.accent : Qt.alpha(card.fg, 0.45)

            Accessible.role: Accessible.Button
            Accessible.name: card.isDefault ? "Salida predeterminada"
                                            : "Hacer salida predeterminada"

            MouseArea {
                anchors.fill: parent
                anchors.margins: -5
                cursorShape: Qt.PointingHandCursor
                onClicked: Pipewire.preferredDefaultAudioSink = card.node
            }
        }

        // Mute: solo aparece en nodos con control de volumen.
        Text {
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
