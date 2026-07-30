pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Cachea las fórmulas de una nota como PNG y avisa cuando hay nuevas: el rich
// text de Qt no tiene motor matemático, lo único que sabe dibujar es un <img>.
// El render lo hace Services/mathrender.py con LaTeX de verdad (latex+dvipng);
// acá solo viven la caché, el hash y el proceso.
//
// Sin texlive el proceso no produce ningún PNG, `has()` sigue devolviendo false
// y el preview deja la fórmula como texto plano — se degrada, no se rompe.
Singleton {
    id: root

    readonly property string cacheDir: Quickshell.cacheDir + "/latex"
    readonly property string _py: Quickshell.shellPath("Services/mathrender.py")

    // Se suma al hash: al cambiar el motor o cómo compone mathrender.py, los
    // PNG viejos dejan de valer y se vuelven a generar solos.
    readonly property int rev: 3

    // Entran en el hash: al cambiar el tema o el cuerpo de letra, las fórmulas
    // se vuelven a renderizar en vez de quedar con el color viejo.
    property color color: "#e6e6e6"
    property int size: 12
    property int dpi: 110

    // Se renderiza a `oversample` veces el tamaño y el <img> se dibuja dividido
    // por lo mismo: a 110 dpi el PNG queda blando al lado del texto vectorial.
    property int oversample: 2

    property var _have: ({})     // hash → true (PNG listo en disco)
    property var _failed: ({})   // hash → true (no se reintenta)
    property var _dim: ({})      // hash → [ancho, alto] ya divididos

    signal rendered()

    function _hash(s) {
        var h = 5381
        for (var i = 0; i < s.length; i++)
            h = ((h * 33) ^ s.charCodeAt(i)) >>> 0
        return h.toString(16)
    }

    function key(tex) {
        return root._hash(tex + "|" + root.color + "|" + root.size + "|"
                          + root.dpi + "|" + root.oversample + "|" + root.rev)
    }

    function pathFor(tex) {
        return root.cacheDir + "/" + root.key(tex) + ".png"
    }

    function has(tex) {
        return root._have[root.key(tex)] === true
    }

    /// [ancho, alto] en px de pantalla, o null si todavía no está renderizada.
    function dimFor(tex) {
        return root._dim[root.key(tex)] || null
    }

    /// Pide el render de las fórmulas que falten. Al terminar emite rendered();
    /// el llamador vuelve a pedir el HTML y ahí ya están los <img>.
    function request(texList) {
        if (proc.running)
            return
        const jobs = []
        const seen = {}
        for (var i = 0; i < texList.length; i++) {
            const tex = texList[i]
            const k = root.key(tex)
            if (root._have[k] || root._failed[k] || seen[k])
                continue
            seen[k] = true
            jobs.push({ key: k, tex: tex, path: root.pathFor(tex) })
        }
        if (jobs.length === 0)
            return

        // Una sola tanda por vez: el script compone todas las fórmulas en un
        // único documento, y arrancar LaTeX es lo caro, no componerlas.
        proc.command = ["python3", root._py, JSON.stringify({
            dir: root.cacheDir,
            color: String(root.color),
            size: root.size * root.oversample,
            dpi: root.dpi,
            jobs: jobs
        })]
        proc.running = true
    }

    Process {
        id: proc
        stdout: StdioCollector {
            id: out
            onStreamFinished: {
                const lines = out.text.split("\n")
                var any = false
                for (var i = 0; i < lines.length; i++) {
                    const parts = lines[i].trim().split(" ")
                    if (parts[0] === "OK" && parts.length === 4) {
                        root._have[parts[1]] = true
                        root._dim[parts[1]] = [Math.round(parseInt(parts[2]) / root.oversample),
                                               Math.round(parseInt(parts[3]) / root.oversample)]
                        any = true
                    } else if (parts[0] === "FAIL" && parts.length === 2) {
                        root._failed[parts[1]] = true
                    }
                }
                if (any)
                    root.rendered()
            }
        }
    }
}
