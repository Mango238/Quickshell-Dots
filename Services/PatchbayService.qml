pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * PatchbayService — la única parte del patchbay que sale al mundo exterior.
 *
 * Nodos, links, volumen y picos vienen del módulo nativo `Quickshell.Services.Pipewire`,
 * reactivo y sin parseo (misma regla que WifiService: si hay módulo nativo, se usa). Pero
 * la API nativa NO expone puertos, y `pw-link` necesita un port-id por canal para crear un
 * link. Así que este singleton hace solo dos cosas:
 *
 *   1. Mantiene el inventario de puertos leído de `pw-dump` (solo mientras `active`).
 *   2. Ejecuta las mutaciones con `pw-link`, siempre por ids numéricos — los nodos reales
 *      se llaman cosas como `ALSA plug-in [spotifyd]`, con espacios y corchetes; quotear
 *      eso es pedir problemas.
 *
 * Nunca actúa solo: no reintenta, no reconecta, no toca el sink por defecto.
 * scripts/eq_filter_chain.sh también mueve links, y dos cosas automáticas peleándose por
 * el ruteo es como uno se queda sin audio.
 */
Singleton {
    id: root

    // nodeId -> { out: [{ id, ch }], in: [{ id, ch }] }
    property var portsByNode: ({})
    // Último fallo de pw-link/pw-dump, para mostrarlo en la UI. "" = sin error.
    property string lastError: ""

    // Solo refresca mientras la ventana del patchbay está abierta: pw-dump son 350 KB
    // y no tiene sentido pagarlos con el patchbay cerrado.
    property bool active: false
    onActiveChanged: if (active) refresh()

    // Un refresco pedido mientras hay un dump en vuelo NO se puede tirar: el debounce de
    // abajo no repite, así que ese refresco se perdía para siempre. Pasaba de verdad al
    // abrir Spotify (ráfaga de nodos): el dump anterior seguía corriendo, portsByNode no
    // aprendía los puertos del nodo nuevo, y su pin de salida no aparecía — la tarjeta era
    // inconectable hasta que algún evento no relacionado disparara otro refresh.
    property bool _pending: false

    function refresh() {
        if (dumpProc.running) { root._pending = true; return }
        dumpProc.running = true
    }

    // Crea un link por cada par de canales entre srcId y dstId.
    function connectNodes(srcId, dstId) {
        const outs = (portsByNode[srcId] || {}).out || []
        const ins = (portsByNode[dstId] || {}).in || []
        if (outs.length === 0 || ins.length === 0) {
            root.lastError = "Sin puertos compatibles entre los dos nodos"
            return
        }

        const pairs = []
        if (outs.length === 1 && ins.length > 1) {
            // Mono hacia estéreo: la misma salida alimenta todas las entradas.
            for (let i = 0; i < ins.length; i++)
                pairs.push([outs[0].id, ins[i].id])
        } else {
            for (let k = 0; k < outs.length; k++) {
                // Emparejar por canal (FL con FL); si el puerto no declara canal, caer a
                // emparejado por índice. Buscar match SOLO cuando hay canal es lo que hace
                // alcanzable ese fallback: antes jq metía "MONO" por defecto, así que sin
                // canales declarados TODOS coincidían y find() acertaba siempre en ins[0]
                // — dos salidas terminaban en la misma entrada y se perdía un canal.
                const match = outs[k].ch ? ins.find(p => p.ch === outs[k].ch) : null
                pairs.push([outs[k].id, (match || ins[k % ins.length]).id])
            }
        }

        _mutate(_joinChecked(pairs.map(p => `pw-link ${p[0]} ${p[1]}`)))
    }

    // `a; b` en sh devuelve el estado del ÚLTIMO comando, así que un pw-link que fallaba
    // ("File exists") seguido de otro que andaba salía 0: link a medias reportado como
    // éxito. Se corren todos igual (abortar al primero dejaría el link a medias) pero el
    // fallo se acumula y sale por el exit code.
    function _joinChecked(cmds) {
        return cmds.map(c => c + " || e=1").join("; ") + "; exit ${e:-0}"
    }

    // Un solo pw-link por link real. Los ids salen de Pipewire.links (PwLink.id), que es
    // lo que PwLinkGroup no expone: el grupo agrega los canales pero no guarda sus ids.
    function disconnectLinks(linkIds) {
        if (linkIds.length === 0) return
        _mutate(_joinChecked(linkIds.map(id => `pw-link -d ${id}`)))
    }

    function _mutate(shellCommand) {
        if (mutateProc.running) {
            root.lastError = "pw-link ocupado, reintenta"
            return
        }
        root.lastError = ""
        mutateProc.err = ""
        mutateProc.command = ["sh", "-c", shellCommand]
        mutateProc.running = true
    }

    // `values` de un ObjectModel notifica (valuesChanged), así que esto cubre tanto
    // nodos nuevos como links nuevos. Debounce porque abrir Spotify emite una ráfaga.
    Connections {
        target: Pipewire.nodes
        function onValuesChanged() { if (root.active) debounce.restart() }
    }

    Connections {
        target: Pipewire.links
        function onValuesChanged() { if (root.active) debounce.restart() }
    }

    Timer {
        id: debounce
        interval: 150
        onTriggered: root.refresh()
    }

    // jq en vez de parsear en QML: pw-dump son ~350 KB de JSON y solo interesan los
    // ~40 objetos Port. `info.direction` es "input"/"output" desde el punto de vista
    // del nodo, así que un sink expone sus playback_* como "input".
    Process {
        id: dumpProc
        running: false
        // `set -o pipefail` porque el exit de una pipe es el del ÚLTIMO comando: sin él,
        // con pw-dump ausente o roto jq recibía entrada vacía, no emitía nada y salía 0.
        // El fallo llegaba disfrazado de "pw-dump ilegible" (por el JSON.parse("")) y
        // onExited nunca reportaba nada. /bin/sh es bash acá, pipefail está disponible.
        // Sin `//"MONO"` en el canal: que llegue null es lo que deja usar el fallback por
        // índice en connectNodes.
        command: ["sh", "-c",
            "set -o pipefail; pw-dump | jq -c '[.[]|select(.type==\"PipeWire:Interface:Port\")"
            + "|{i:.id,n:.info.props[\"node.id\"],d:.info.direction,"
            + "c:.info.props[\"audio.channel\"]}]'"]

        // El resultado del parseo se guarda acá en vez de escribir lastError directo:
        // onExited es el único que lo decide (ver abajo).
        property string dumpErr: ""

        stdout: StdioCollector {
            onStreamFinished: {
                dumpProc.dumpErr = ""
                let ports
                try {
                    ports = JSON.parse(this.text)
                } catch (e) {
                    dumpProc.dumpErr = "pw-dump ilegible: " + e
                    return
                }
                const map = {}
                for (let i = 0; i < ports.length; i++) {
                    const p = ports[i]
                    if (p.n === undefined || p.n === null) continue
                    if (!map[p.n]) map[p.n] = { out: [], in: [] }
                    map[p.n][p.d === "output" ? "out" : "in"].push({ id: p.i, ch: p.c })
                }
                root.portsByNode = map
            }
        }

        // Único sitio que escribe lastError en el camino del dump: un dump correcto tiene
        // que LIMPIARLO. Antes solo se escribía y nunca se borraba, así que un fallo
        // puntual dejaba el banner de error puesto el resto de la sesión.
        // (onStreamFinished no dispara si el binario no existe, ver WallpaperService.)
        onExited: code => {
            root.lastError = code !== 0
                ? "pw-dump/jq falló (código " + code + ")"
                : dumpProc.dumpErr

            // callLater: no reentrar en running desde el propio onExited del proceso.
            if (root._pending && root.active) {
                root._pending = false
                Qt.callLater(root.refresh)
            }
        }
    }

    Process {
        id: mutateProc
        running: false
        command: []
        property string err: ""
        stderr: SplitParser { onRead: data => { mutateProc.err += data + "\n" } }
        onExited: code => {
            if (code !== 0)
                root.lastError = mutateProc.err.trim() || ("pw-link falló (código " + code + ")")
        }
    }
}
