import QtQuick
import QtQuick.Shapes
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Services

/**
 * El grafo: coloca los nodos en tres columnas por rol, dibuja los cables y maneja el
 * arrastre para crear links.
 *
 * Todo el estado sale de `Quickshell.Services.Pipewire`, que es reactivo (`values` de un
 * ObjectModel notifica). No hay refresco manual: si desconectas el auricular bluetooth,
 * su tarjeta y sus cables se van solos.
 *
 * Las posiciones NO se persisten. Los nodos de aplicación (spotifyd, Brave) cambian de id
 * en cada arranque, así que guardarlas obligaría a purgar huérfanas cada vez; al reabrir
 * el patchbay se recolocan solos.
 */
Item {
    id: root

    // La ventana está visible: enciende los peak monitors de las tarjetas.
    property bool live: true

    // Cable elástico mientras se arrastra desde un pin de salida.
    property int linkingFrom: -1
    property real dragX: 0
    property real dragY: 0

    readonly property real cardWidth: 220
    readonly property real columnGap: 120
    readonly property real rowGap: 76

    function colX(col) { return 30 + col * (root.cardWidth + root.columnGap) }
    function rowY(row) { return 20 + row * root.rowGap }

    // ── Registro de tarjetas ────────────────────────────────────────────────
    // Los cables necesitan la x/y viva de sus dos extremos. Mutar un `var` no notifica,
    // así que `cardRev` es la dependencia que hace revaluar los bindings de `cardOf`.
    property var cards: ({})
    property int cardRev: 0

    function registerCard(nodeId, item) { root.cards[nodeId] = item; root.cardRev++ }
    function unregisterCard(nodeId) { delete root.cards[nodeId]; root.cardRev++ }
    function cardOf(nodeId) {
        return root.cardRev >= 0 ? (root.cards[nodeId] || null) : null
    }

    // ── Clasificación ───────────────────────────────────────────────────────
    // Por los flags de `type`, NO por properties["media.class"]: `properties` solo se
    // puebla en nodos que ya bindeó un PwObjectTracker, y aquí hace falta clasificar
    // *antes* de decidir a quién bindear. `type` en cambio viene lleno desde el
    // descubrimiento. Lo que no lleva el bit Audio (midi, cámaras v4l2, Dummy-Driver,
    // Freewheel-Driver) no se dibuja.
    function roleOf(node) {
        const t = node.type
        if ((t & PwNodeType.Audio) === 0) return -1
        // Nuestras propias capturas: cada PwNodePeakMonitor abre un stream que PipeWire
        // registra como nodo. Sin este filtro el grafo se los dibuja, les pone otro
        // monitor, y eso crea más nodos — realimentación pura, con el loop de PipeWire
        // escupiendo "no global ... any more" mientras nacen y mueren.
        if (node.name === "quickshell") return -1
        // En un stream los flags van desde el punto de vista del dispositivo: el que
        // reproduce (AudioOutStream, p.ej. spotifyd) lleva el bit Sink, y el que graba
        // (AudioInStream) lleva el Source. Es el revés de un nodo de dispositivo.
        if (t & PwNodeType.Stream) return (t & PwNodeType.Sink) ? 0 : 2
        // Entra y sale a la vez: es un filtro — ahí cae el filter-chain del ecualizador.
        if ((t & PwNodeType.Source) && (t & PwNodeType.Sink)) return 1
        return (t & PwNodeType.Sink) ? 2 : 0
    }

    readonly property var groups: Pipewire.linkGroups ? Pipewire.linkGroups.values : []

    // Un nodo que es a la vez origen y destino de algún link es un filtro — ahí cae el
    // filter-chain del ecualizador. Va en la columna del medio, entre fuentes y salidas.
    readonly property var midIds: {
        const src = {}, dst = {}, mid = {}
        for (let i = 0; i < root.groups.length; i++) {
            const g = root.groups[i]
            if (g.source) src[g.source.id] = true
            if (g.target) dst[g.target.id] = true
        }
        for (const k in src) if (dst[k]) mid[k] = true
        return mid
    }

    readonly property var linkedIds: {
        const s = {}
        for (let i = 0; i < root.groups.length; i++) {
            const g = root.groups[i]
            if (g.source) s[g.source.id] = true
            if (g.target) s[g.target.id] = true
        }
        return s
    }

    // Lista plana con columna y fila ya resueltas, para un solo Repeater.
    readonly property var placed: {
        const cols = [[], [], []]
        const all = Pipewire.nodes ? Pipewire.nodes.values : []
        for (let i = 0; i < all.length; i++) {
            const n = all[i]
            const r = root.roleOf(n)
            if (r < 0) continue
            cols[root.midIds[n.id] ? 1 : r].push(n)
        }
        const out = []
        for (let c = 0; c < 3; c++)
            for (let k = 0; k < cols[c].length; k++)
                out.push({ node: cols[c][k], col: c, row: k })
        return out
    }

    readonly property var trackedNodes: root.placed.map(p => p.node)

    // Sin esto los objetos llegan sin bindear: ni volumen, ni picos, ni cambios.
    PwObjectTracker { objects: root.trackedNodes }

    // ── Acciones ────────────────────────────────────────────────────────────

    function endLink(x, y) {
        const src = root.linkingFrom
        root.linkingFrom = -1
        if (src < 0) return
        for (const id in root.cards) {
            if (Number(id) === src) continue
            const c = root.cards[id]
            if (x >= c.x && x <= c.x + c.width && y >= c.y && y <= c.y + c.height) {
                PatchbayService.connectNodes(src, Number(id))
                return
            }
        }
    }

    function disconnectGroup(group) {
        if (!group.source || !group.target) return
        const ids = []
        const links = Pipewire.links ? Pipewire.links.values : []
        for (let i = 0; i < links.length; i++) {
            const l = links[i]
            if (l.source && l.target
                && l.source.id === group.source.id
                && l.target.id === group.target.id)
                ids.push(l.id)
        }
        PatchbayService.disconnectLinks(ids)
    }

    // ── Dibujo ──────────────────────────────────────────────────────────────
    // Los cables van declarados antes que las tarjetas para quedar por debajo.

    Repeater {
        model: root.groups
        delegate: Cable {
            required property var modelData
            linkGroup: modelData
            graph: root
        }
    }

    // Cable elástico del arrastre en curso.
    // Ojo: ShapePath y PathCubic no son Items, así que `parent` dentro de ellos no
    // resuelve al Shape. Hay que referenciarlo por id.
    Shape {
        id: rubber

        anchors.fill: parent
        visible: root.linkingFrom >= 0
        preferredRendererType: Shape.CurveRenderer

        readonly property var origin: root.cardOf(root.linkingFrom)
        readonly property real ax: origin ? origin.x + origin.width : 0
        readonly property real ay: origin ? origin.y + origin.height / 2 : 0

        ShapePath {
            strokeColor: Colors.accent
            strokeWidth: 2
            strokeStyle: ShapePath.DashLine
            dashPattern: [4, 4]
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: rubber.ax
            startY: rubber.ay
            PathCubic {
                x: root.dragX; y: root.dragY
                control1X: rubber.ax + 60; control1Y: rubber.ay
                control2X: root.dragX - 60; control2Y: root.dragY
            }
        }
    }

    Repeater {
        model: root.placed
        delegate: PatchNode {
            required property var modelData
            node: modelData.node
            graph: root
            linked: root.linkedIds[modelData.node.id] === true
            x: root.colX(modelData.col)
            y: root.rowY(modelData.row)
            Component.onCompleted: root.registerCard(modelData.node.id, this)
            Component.onDestruction: root.unregisterCard(modelData.node.id)
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.placed.length === 0
        text: "Sin nodos de audio"
        font.family: Config.font
        font.pixelSize: 13
        color: Qt.alpha(Colors.palette[7], 0.5)
    }

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        elide: Text.ElideRight
        visible: PatchbayService.lastError !== ""
        text: PatchbayService.lastError
        font.family: Config.font
        font.pixelSize: 11
        color: Colors.danger
    }
}
