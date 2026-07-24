pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

/**
 * WallpaperService.qml — Fuente de verdad para el selector de wallpapers.
 *
 * Responsabilidades:
 *   - Escanear wallpaperDir y exponer la lista de imágenes encontradas.
 *   - Saber cuál está aplicado ahora mismo (parseando `awww query`, no un
 *     archivo de estado propio — así nunca se desincroniza si el wallpaper
 *     se cambió por otro medio, p. ej. un script o `awww` desde la terminal).
 *   - Aplicar un wallpaper nuevo con `awww img`. Como no pasamos --outputs,
 *     awww lo aplica a todas las pantallas por defecto (ver docs de awww).
 *   - Si `awww-daemon` no está corriendo, lo levanta una vez y reintenta.
 *
 * Para registrar el singleton, en tu qmldir (junto a los demás):
 *   singleton WallpaperService 1.0 WallpaperService.qml
 */
QtObject {
    id: root

    // ─── Configuración ──────────────────────────────────────────────────────

    /// Carpeta a escanear. Por defecto ~/Imágenes/archlinux-favorite-wallpapers/.
    property string wallpaperDir: Quickshell.env("HOME") + "/Imágenes/archlinux-favorite-wallpapers/"
    
    property string stateFilePath: "/tmp/actual_wallpaper.txt"

    /// Extensiones consideradas como wallpaper válido.
    property var extensions: ["jpg", "jpeg", "png", "webp", "bmp"]

    /// Opciones de transición de awww. Ver `awww img --help` para más tipos
    /// (grow, wipe, wave, outer, random, none, etc.).
    property string transitionType: "grow"
    property real transitionDuration: 0.6
    property int transitionFps: 60

    // Substrings (case-insensitive) que indican que el fallo de `awww img`
    // fue por falta de daemon, y por lo tanto vale la pena reintentar.
    // Si tu versión de awww devuelve otro mensaje, ajustá esta lista.
    property var daemonMissingHints: [
        "connection refused",
        "no such file or directory",
        "failed to connect",
        "could not connect"
    ]

    // ─── Estado observable ──────────────────────────────────────────────────

    /// Lista de paths absolutos (strings) encontrados en wallpaperDir.
    property var wallpapers: []

    /// Path del wallpaper actualmente aplicado, según `awww query`.
    /// Cadena vacía si todavía no se pudo determinar.
    property string currentWallpaper: ""

    /// Paths por monitor cuando `awww query` reporta salidas con wallpapers
    /// distintos (ej. cambiados con --outputs por fuera de este servicio).
    /// currentWallpaper siempre refleja el primero, por compatibilidad.
    property var currentWallpapersByOutput: ({})

    property bool scanning: false
    property bool applying: false

    // ─── Orden de la grilla ─────────────────────────────────────────────────

    /// Modo de orden: "nombre" (alfabético), "tono" (arcoíris: saturados por
    /// hue, grises al final por luminancia) o "luz" (oscuro → claro).
    /// Cambiarlo reordena; si faltan claves de color, primero se analizan
    /// los wallpapers que falten y se reordena al completar.
    property string sortMode: "nombre"

    /// true mientras el ColorQuantizer recorre la cola de análisis.
    property bool analyzing: false
    property int analyzeDone: 0
    property int analyzeTotal: 0

    /// Umbral de saturación bajo el cual un wallpaper cuenta como "gris"
    /// en el modo tono (va al final, ordenado por luminancia).
    property real grayThreshold: 0.15

    /// path → { h, s, l }: hue/saturación HSV (0..1) del color dominante y
    /// luminancia WCAG. Se muta in-place; emitimos colorKeysChanged() a mano.
    property var colorKeys: ({})

    // Cola de análisis y path en curso. El resultado de cada cuantización se
    // atribuye a _analyzingPath (y el quantizer es una instancia por imagen,
    // ver _quantizerComp), nunca a una variable capturada en un closure.
    property var _pendingQueue: []
    property string _analyzingPath: ""

    onSortModeChanged: {
        if (root.sortMode === "nombre") root._applySort()
        else root._ensureAnalyzed()
    }

    /// Filtro por bucket de color ("" = todos). Ver colorBuckets.
    property string colorFilter: ""

    /// Buckets de tono para el filtro; from/to en fracción de hue 0..1
    /// (grados/360). "gris" no usa rango: es todo lo que quede bajo
    /// grayThreshold de saturación.
    readonly property var colorBuckets: [
        { id: "rojo",     from: 345/360, to: 15/360,  swatch: "#e05f5f" },
        { id: "naranja",  from: 15/360,  to: 45/360,  swatch: "#e0955f" },
        { id: "amarillo", from: 45/360,  to: 75/360,  swatch: "#e0d05f" },
        { id: "verde",    from: 75/360,  to: 165/360, swatch: "#6fbf6f" },
        { id: "cian",     from: 165/360, to: 200/360, swatch: "#5fc9c9" },
        { id: "azul",     from: 200/360, to: 260/360, swatch: "#5f87e0" },
        { id: "violeta",  from: 260/360, to: 300/360, swatch: "#9b6fe0" },
        { id: "rosa",     from: 300/360, to: 345/360, swatch: "#e06fb8" },
        { id: "gris",     from: -1,      to: -1,      swatch: "#9399b2" }
    ]

    /// Bucket al que pertenece una clave de color, o null si aún no hay clave.
    function _bucketOf(key) {
        if (!key) return null
        if (key.s < root.grayThreshold) return "gris"
        for (var i = 0; i < root.colorBuckets.length; i++) {
            var b = root.colorBuckets[i]
            if (b.from < 0) continue
            // El rojo cruza el 0 de la rueda de hue (from > to)
            var inRange = b.from > b.to
                ? (key.h >= b.from || key.h < b.to)
                : (key.h >= b.from && key.h < b.to)
            if (inRange) return b.id
        }
        return null
    }

    /// Lista que consume la grilla: wallpapers (ya ordenada) filtrada por
    /// colorFilter. Se re-evalúa con wallpapersChanged y con los
    /// colorKeysChanged() manuales que emite el análisis.
    readonly property var visibleWallpapers: {
        if (root.colorFilter === "") return root.wallpapers
        return root.wallpapers.filter(p => root._bucketOf(root.colorKeys[p]) === root.colorFilter)
    }

    /// id de bucket → cantidad de wallpapers actuales en él. La UI solo
    /// muestra swatches de buckets con al menos uno.
    readonly property var bucketCounts: {
        var counts = {}
        for (var i = 0; i < root.wallpapers.length; i++) {
            var b = root._bucketOf(root.colorKeys[root.wallpapers[i]])
            if (b) counts[b] = (counts[b] || 0) + 1
        }
        return counts
    }

    /// Se emite si una aplicación de wallpaper falla incluso tras reintentar
    /// (por ejemplo, awww no está instalado). El mensaje es apto para mostrar
    /// directo en la UI.
    signal applyFailed(string message)

    // ─── Análisis de color dominante (para ordenar por color) ───────────────

    // Un ColorQuantizer NUEVO por imagen, con source fijado en la creación.
    // No se recicla uno solo cambiando source: al reasignar source dentro del
    // propio handler de colorsChanged aparecían emisiones atribuidas al path
    // siguiente de la cola (claves duplicadas en pares, verificado con logs).
    // Con una instancia por imagen la atribución es inequívoca.
    readonly property Component _quantizerComp: Component {
        ColorQuantizer {
            depth: 3          // 8 colores: suficiente para elegir un dominante
            rescaleSize: 48   // clave de orden, no paleta de UI: chico y rápido
        }
    }
    property var _activeQuantizer: null

    function _onQuantized() {
        var quant = root._activeQuantizer
        if (!quant || root._analyzingPath === "") return
        var cols = quant.colors
        if (!cols || cols.length === 0) return   // esperar la emisión con datos
        quant.colorsChanged.disconnect(root._onQuantized)  // procesar una sola vez
        root.colorKeys[root._analyzingPath] = root._dominantKey(cols)
        root.colorKeysChanged()
        root.analyzeDone++
        root._analyzeNext()
    }

    function _destroyQuantizer() {
        if (!root._activeQuantizer) return
        root._activeQuantizer.destroy()
        root._activeQuantizer = null
    }

    // Si dos imágenes consecutivas cuantizan a la MISMA lista de colores,
    // colorsChanged no se emite (la propiedad no cambió) y la cola quedaría
    // colgada; también cubre decodes que fallan en silencio. El watchdog
    // saltea el elemento en curso.
    readonly property Timer analyzeWatchdog: Timer {
        interval: 4000
        onTriggered: {
            if (root._analyzingPath === "") return
            console.warn("WallpaperService: análisis sin respuesta, salteando", root._analyzingPath)
            root.colorKeys[root._analyzingPath] = { h: 0, s: 0, l: 0 }
            root.analyzeDone++
            root._analyzeNext()
        }
    }

    // Scoring de dominante al estilo _pickAccent de DankMaterialShell:
    // descarta extremos de brillo y colores lavados, puntúa saturación
    // cerca de un brillo medio. Fallback: primer color (imágenes grises).
    function _dominantKey(colors) {
        var best = null, bestScore = -1
        for (var i = 0; i < colors.length; i++) {
            var c = colors[i]
            var s = c.hsvSaturation, v = c.hsvValue
            if (v < 0.22 || v > 0.96 || s < 0.22) continue
            var score = s * (1 - Math.abs(v - 0.68))
            if (score > bestScore) { bestScore = score; best = c }
        }
        if (!best && colors.length > 0) best = colors[0]
        if (!best) return { h: 0, s: 0, l: 0 }
        return {
            h: best.hsvHue < 0 ? 0 : best.hsvHue,   // hsvHue = -1 en acromáticos
            s: best.hsvSaturation,
            l: OrderColors.getLuminance(best.toString())
        }
    }

    /// Encola los wallpapers sin clave de color; si no falta ninguno,
    /// reordena de inmediato.
    function _ensureAnalyzed() {
        var missing = root.wallpapers.filter(p => !root.colorKeys[p])
        if (missing.length === 0) { root._applySort(); return }
        root._pendingQueue = missing
        root.analyzeTotal = missing.length
        root.analyzeDone = 0
        root.analyzing = true
        root._analyzeNext()
    }

    function _analyzeNext() {
        root._destroyQuantizer()
        var q = root._pendingQueue
        if (q.length === 0) {
            root.analyzing = false
            root._analyzingPath = ""
            root.analyzeWatchdog.stop()
            root._saveCache()
            root._applySort()      // reordena UNA vez, al completar
            return
        }
        root._analyzingPath = q.shift()
        root._pendingQueue = q
        root.analyzeWatchdog.restart()
        root._activeQuantizer = root._quantizerComp.createObject(root, {
            source: "file://" + root._analyzingPath
        })
        root._activeQuantizer.colorsChanged.connect(root._onQuantized)
        root._onQuantized()   // por si la cuantización fue sincrónica (caché de Qt)
    }

    function _cancelAnalysis() {
        root._destroyQuantizer()
        root._pendingQueue = []
        root._analyzingPath = ""
        root.analyzing = false
        root.analyzeWatchdog.stop()
    }

    function _byPath(a, b) { return a < b ? -1 : (a > b ? 1 : 0) }

    function _applySort() {
        var list = root.wallpapers.slice()
        if (root.sortMode === "luz") {
            list.sort((a, b) => {
                var ka = root.colorKeys[a], kb = root.colorKeys[b]
                var d = (ka ? ka.l : 0) - (kb ? kb.l : 0)
                return d !== 0 ? d : root._byPath(a, b)
            })
        } else if (root.sortMode === "tono") {
            list.sort((a, b) => {
                var ka = root.colorKeys[a] || { h: 0, s: 0, l: 0 }
                var kb = root.colorKeys[b] || { h: 0, s: 0, l: 0 }
                var ga = ka.s < root.grayThreshold
                var gb = kb.s < root.grayThreshold
                if (ga !== gb) return ga ? 1 : -1          // grises al final
                var d = ga ? (ka.l - kb.l) : (ka.h - kb.h) // grises por luz, resto arcoíris
                if (d === 0) d = ka.l - kb.l               // mismo hue → por luz
                return d !== 0 ? d : root._byPath(a, b)
            })
        } else {
            list.sort(root._byPath)                        // "nombre"
        }
        root.wallpapers = list   // reasignar reconstruye la vista sola
    }

    // ─── Caché persistente de claves de color ────────────────────────────────

    property string colorCacheDir:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/quickshell"

    readonly property FileView cacheFile: FileView {
        path: root.colorCacheDir + "/wallpaper-colors.json"
        printErrors: false    // primer arranque: el archivo no existe aún
        onLoaded: {
            try {
                var parsed = JSON.parse(this.text())
                // Lo ya computado en esta sesión gana sobre lo cacheado
                root.colorKeys = Object.assign({}, parsed, root.colorKeys)
            } catch (e) {
                console.warn("WallpaperService: caché de colores corrupto, ignorando:", e)
            }
        }
        onSaveFailed: (error) => console.warn("WallpaperService: no se pudo guardar el caché de colores:", error)
    }

    function _saveCache() {
        cacheFile.setText(JSON.stringify(root.colorKeys))
    }

    /// Borra las claves de color (memoria; el disco se reescribe en el
    /// próximo análisis). La usa el botón ⟳ como invalidación manual
    /// (la clave es el path, sin mtime).
    function invalidateColorCache() {
        root._cancelAnalysis()
        root.colorKeys = ({})
    }

    // ─── Escaneo de la carpeta ───────────────────────────────────────────────

    function scan() {
        if (root.scanning) return
        root.scanning = true
        // Un rescan (p. ej. cambio de wallpaperDir) invalida la cola en
        // curso; el colorsChanged rezagado cae en el guard de _analyzingPath.
        // El filtro también se resetea: los buckets del directorio nuevo
        // pueden no incluir el activo.
        root._cancelAnalysis()
        root.colorFilter = ""

        // Paso 1: encontrar todos los archivos con extensión de imagen
        var args = ["find", root.wallpaperDir, "-maxdepth", "1", "-type", "f", "("]
        for (var i = 0; i < root.extensions.length; i++) {
            if (i > 0) args.push("-o")
            args.push("-iname")
            args.push("*." + root.extensions[i])
        }
        args.push(")")

        scanProc.command = args
        scanProc.running = true
    }

    readonly property Process scanProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n").filter(l => l.trim().length > 0)
                lines.sort()
                // Paso 2: validar cada archivo con `file` para detectar
                // formatos realmente soportados (evita archivos corruptos)
                validateImages(lines)
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Si find falló (o no existe en PATH), no hay nada que validar.
            // stdout.onStreamFinished puede no dispararse en absoluto en ese
            // caso, así que cortamos el flujo acá.
            if (exitCode !== 0) {
                root.wallpapers = []
                root.scanning = false
            }
        }
    }

    function validateImages(files) {
        root.wallpapers = []

        if (files.length === 0) {
            root.scanning = false
            return
        }

        var args = ["file", "--mime-type"].concat(files)
        validateProc.command = args
        validateProc.running = true
    }

    readonly property Process validateProc: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                // FIX: procesamos acá (cuando el stream realmente terminó de
                // leerse), no en onExited del proceso — son señales
                // independientes y onExited puede dispararse antes de que
                // stdout termine de streamear, sobre todo con listas largas.
                var lines = this.text.split("\n").filter(l => l.trim().length > 0)

                // Aceptamos solo formatos que Qt sabe decodificar
                var validMimes = [
                    "image/jpeg",
                    "image/png",
                    "image/webp",
                    "image/bmp",
                    "image/tiff",
                    "image/x-ms-bmp"
                ]

                var found = []
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i]
                    // Formato: "/ruta/archivo: image/png"
                    // Usamos el PRIMER ":" como separador — el path nunca
                    // debería tener uno en un filesystem típico, pero por
                    // las dudas usamos indexOf en vez de split(":") para no
                    // depender de que no haya más de un ":" en la línea.
                    var sepIdx = line.indexOf(":")
                    if (sepIdx === -1) continue

                    var filePath = line.slice(0, sepIdx).trim()
                    var mimeType = line.slice(sepIdx + 1).trim()

                    if (validMimes.some(mime => mimeType.startsWith(mime))) {
                        found.push(filePath)
                    }
                }
                root.wallpapers = found
                root.scanning = false
                // Siempre: los swatches del filtro por color necesitan las
                // claves aunque el orden sea "nombre". Con caché caliente es
                // inmediato; en frío corre asíncrono sin bloquear.
                root._ensureAnalyzed()
            }
        }
        onExited: (exitCode, exitStatus) => {
            // Si `file` no existe o falló al spawnear, stdout.onStreamFinished
            // puede no llegar nunca — nos aseguramos de no quedar colgados.
            if (exitCode !== 0 && root.scanning) {
                root.wallpapers = []
                root.scanning = false
            }
        }
    }

    // ─── Detección del wallpaper actual (vía `awww query`) ──────────────────

    function refreshCurrent() {
        queryProc.running = true
    }

    readonly property Process queryProc: Process {
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                // FIX: `awww query` imprime una línea por monitor. Antes
                // usábamos .match() sin flag global, que solo captura la
                // primera línea. Ahora recorremos todas las líneas y
                // guardamos el mapeo completo, manteniendo currentWallpaper
                // como el primero encontrado por compatibilidad.
                var byOutput = {}
                var first = ""
                var lines = this.text.split("\n")

                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i]
                    var outputMatch = line.match(/^([^:]+):/)
                    var imageMatch = line.match(/currently displaying:\s*image:\s*(.+)/)
                    if (imageMatch) {
                        var img = imageMatch[1].trim()
                        var output = outputMatch ? outputMatch[1].trim() : ("output" + i)
                        byOutput[output] = img
                        if (!first) first = img
                    }
                }

                root.currentWallpapersByOutput = byOutput
                if (first) root.currentWallpaper = first
            }
        }
    }

    // ─── Aplicar un wallpaper ────────────────────────────────────────────────

    function apply(path) {
        if (!path || root.applying) return
        root.applying = true
        pendingPath = path
        applyProc.command = buildApplyCommand(path)
        applyProc.running = true
    }

    property string pendingPath: ""
    property bool _retriedOnce: false

    function buildApplyCommand(path) {
        return [
            "awww", "img", path,
            "--transition-type", root.transitionType,
            "--transition-duration", String(root.transitionDuration),
            "--transition-fps", String(root.transitionFps)
        ]
    }

    function _looksLikeDaemonMissing(stderrText) {
        var lower = (stderrText || "").toLowerCase()
        return root.daemonMissingHints.some(hint => lower.indexOf(hint) !== -1)
    }

    readonly property Process applyProc: Process {
        stderr: StdioCollector {
            id: applyStderr
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.applying = false
                root._retriedOnce = false
                // FIX: en vez de asumir que currentWallpaper == pendingPath,
                // confirmamos contra la fuente de verdad real (awww query),
                // coherente con la filosofía del resto del servicio.
                root.refreshCurrent()
                return
            }

            var stderrText = applyStderr.text

            // FIX: solo reintentamos si el error realmente sugiere que el
            // daemon no está corriendo. Antes reintentábamos ante cualquier
            // fallo (path inválido, archivo corrupto, etc.), agregando
            // 700ms de latencia a errores que nunca se iban a resolver.
            if (!root._retriedOnce && root._looksLikeDaemonMissing(stderrText)) {
                root._retriedOnce = true
                Quickshell.execDetached(["awww-daemon"])
                retryTimer.start()
            } else {
                root.applying = false
                root._retriedOnce = false
                root.applyFailed(stderrText || "No se pudo aplicar el wallpaper con awww.")
            }
        }
    }
    onCurrentWallpaperChanged: root._writeCurrentWallpaperFile()

    function _writeCurrentWallpaperFile() {
        if (!root.stateFilePath || !root.currentWallpaper) return

        // FIX: si ya hay una escritura en curso, no lanzamos otra en paralelo
        // sobre el mismo Process (pisaría su .command mientras corre).
        // Es un caso raro (cambios de wallpaper son poco frecuentes), así que
        // simplemente descartamos esta escritura; la próxima señal de cambio
        // va a volver a intentarlo con el valor más reciente.
        if (writeStateProc.running) return

        writeStateProc.command = [
            "sh", "-c", 'printf "%s" "$1" > "$2"',
            "_", root.currentWallpaper, root.stateFilePath
        ]
        writeStateProc.running = true
    }

    readonly property Process writeStateProc: Process {
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0)
                    console.warn("WallpaperService: fallo al escribir stateFilePath:", this.text)
            }
        }
    }

    readonly property Timer retryTimer: Timer {
        interval: 700
        onTriggered: {
            applyProc.command = root.buildApplyCommand(root.pendingPath)
            applyProc.running = true
        }
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.colorCacheDir])
        scan()
        refreshCurrent()
    }
}
