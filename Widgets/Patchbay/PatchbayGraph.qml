pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Services

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
    // Con `item`: el borrado en QML es diferido, así que al recrearse un delegate el
    // onDestruction del viejo puede correr DESPUÉS del onCompleted del nuevo. Sin comparar
    // identidad, el viejo borraba el registro recién puesto: cardOf devolvía null y todos
    // los cables de ese nodo se apagaban (Cable.valid === false) hasta el próximo reset.
    function unregisterCard(nodeId, item) {
        if (root.cards[nodeId] !== item) return
        delete root.cards[nodeId]
        root.cardRev++
    }
    function cardOf(nodeId) {
        return root.cardRev >= 0 ? (root.cards[nodeId] || null) : null
    }

    // ── Lienzo ──────────────────────────────────────────────────────────────
    // Las tarjetas y los cables viven en coordenadas del LIENZO, no del viewport: el
    // Flickable las desplaza por debajo. PatchPin mapea ahí el arrastre y endLink
    // hit-testea ahí.
    readonly property alias canvas: canvasItem

    // Tamaño del lienzo = borde máximo de las tarjetas registradas. Leer c.x/c.y acá las
    // registra como dependencia del binding, así que el lienzo crece EN VIVO mientras se
    // arrastra una tarjeta, sin tocar `pos` (que se muta sin notificar a propósito).
    // `cardRev` cubre el alta/baja de tarjetas, igual que en cardOf().
    // Recorre el registro y NO childrenRect a propósito: los cables llenan el lienzo, así
    // que derivar su tamaño de childrenRect sería un loop de binding.
    readonly property var extent: {
        let w = 0, h = 0
        if (root.cardRev >= 0) for (const id in root.cards) {
            const c = root.cards[id]
            if (!c) continue          // entrada rancia, igual que en endLink
            w = Math.max(w, c.x + c.width)
            h = Math.max(h, c.y + c.height)
        }
        return { w: w + 30, h: h + 20 }   // mismo margen que colX/rowY del otro lado
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

    // ── Posiciones ──────────────────────────────────────────────────────────
    // La posición vive en el grafo, no en la tarjeta: el delegate se destruye y se recrea
    // cuando PipeWire da de alta o de baja un nodo, y con él se iba el arrastre.
    // pos[id] = { col, row, x, y } — `row` es la ranura de rejilla (para no apilar dos
    // tarjetas nuevas encima) y x/y la posición real, fuera de rejilla si se arrastró.
    // Se muta SIN notificar a propósito: los bindings de x/y solo deben releerla al nacer
    // el delegate, no cada vez que se mueve otra tarjeta. Eso es además lo que garantiza
    // que no haya loop: nada de lo que depende `x` se escribe desde `x`.
    // ponytail: el Loader de Modules/Patchbay.qml destruye el grafo al cerrar la ventana,
    // así que las posiciones no sobreviven a cerrar/abrir. Si molesta, subir `pos` a
    // Patchbay.qml y pasarlo hacia abajo.
    property var pos: ({})

    function colOf(node) { return root.midIds[node.id] ? 1 : root.roleOf(node) }

    function slotFor(nodeId, col) {
        const p = root.pos[nodeId]
        if (p && p.col === col) return p
        const taken = {}
        for (const k in root.pos) {
            const q = root.pos[k]
            if (q.col === col && Number(k) !== nodeId) taken[q.row] = true
        }
        let r = 0
        while (taken[r]) r++
        const np = { col: col, row: r, x: root.colX(col), y: root.rowY(r) }
        root.pos[nodeId] = np
        return np
    }

    function savePos(nodeId, x, y) {
        const p = root.pos[nodeId]
        if (p) { p.x = x; p.y = y }
    }

    // Nodos de audio vivos, ordenados por id — orden estable, a diferencia del de
    // Pipewire.nodes.values, cuyo índice de inserción hacía saltar de fila a tarjetas que
    // no habían cambiado en nada. Ya no depende de midIds: la columna se resuelve en el
    // binding de cada tarjeta, así que conectar un filtro mueve UNA tarjeta en vez de
    // reconstruir la lista entera.
    // El podado va acá dentro a propósito: es lo único que corre con la lista nueva ANTES
    // de que el Repeater cree los delegates que leen `pos`. Sin él las ranuras de los
    // nodos muertos siguen ocupadas y cada tarjeta nueva cae más abajo hasta salirse.
    readonly property var placed: {
        const out = []
        const all = Pipewire.nodes ? Pipewire.nodes.values : []
        for (let i = 0; i < all.length; i++)
            if (root.roleOf(all[i]) >= 0) out.push(all[i])
        out.sort((a, b) => a.id - b.id)
        const live = {}
        for (let i = 0; i < out.length; i++) live[out[i].id] = true
        for (const k in root.pos) if (!live[k]) delete root.pos[k]
        return out
    }

    // Sin esto los objetos llegan sin bindear: ni volumen, ni picos, ni cambios.
    PwObjectTracker { objects: root.placed }

    // ── Acciones ────────────────────────────────────────────────────────────

    function endLink(x, y) {
        const src = root.linkingFrom
        root.linkingFrom = -1
        if (src < 0) return
        for (const id in root.cards) {
            if (Number(id) === src) continue
            const c = root.cards[id]
            // Una entrada rancia (nodo que desapareció a mitad del arrastre: auricular
            // bluetooth, stream que termina) tiraba un TypeError acá que abortaba el
            // intento de conexión en silencio, sin siquiera poner lastError.
            if (!c) continue
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
    // El Flickable es el viewport; canvasItem es el contenido y crece con las tarjetas.
    // Arrastrar el fondo panea el lienzo (estilo Google Maps). Arrastrar una tarjeta la
    // mueve y arrastrar un pin tira cable: los dos ganan con preventStealing en su
    // MouseArea, sin lo cual el Flickable les roba el grab pasado el umbral de arrastre.
    Flickable {
        id: view

        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: Math.max(view.width, root.extent.w)
        contentHeight: Math.max(view.height, root.extent.h)
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

        Item {
            id: canvasItem

            width: view.contentWidth
            height: view.contentHeight

            // Afordancia de "esto se arrastra". HoverHandler es pasivo: nunca agarra el
            // puntero, así que no le quita el press ni al Flickable ni a las tarjetas.
            HoverHandler {
                cursorShape: view.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            }

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

            // ScriptModel convierte el cambio de array en inserciones/borrados en vez de un
            // reset, así que un nodo nuevo ya no destruye los delegates de los demás — ni con
            // ellos sus PwNodePeakMonitor, que son capturas de stream reales y vuelven a
            // aparecer en PipeWire como nodos nuevos. Con un array plano eso se realimentaba.
            // Se le pasan PwNode pelados, no literales {node,col,row}: esos se re-asignan en
            // cada evaluación, la identidad nunca coincide y el diff no serviría de nada.
            Repeater {
                model: ScriptModel { values: root.placed }
                delegate: PatchNode {
                    required property var modelData
                    node: modelData
                    graph: root
                    linked: root.linkedIds[modelData.id] === true
                    x: root.slotFor(modelData.id, root.colOf(modelData)).x
                    y: root.slotFor(modelData.id, root.colOf(modelData)).y
                    Component.onCompleted: root.registerCard(modelData.id, this)
                    Component.onDestruction: root.unregisterCard(modelData.id, this)
                }
            }
        }
    }

    // Los dos textos de abajo van FUERA del Flickable a propósito: quedan fijos al viewport
    // y no se van paneando con el lienzo.
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
