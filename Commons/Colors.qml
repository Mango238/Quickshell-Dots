pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: colors

    // ── Estado público (semáforo) ──────────────────────────────────
    property bool ready: false
    property string wallpaperPath: ""
    property var palette: []

    // ── Roles semánticos derivados (uso directo en widgets) ─────────
    // accent: acento interactivo/borde fino (mismo índice que ya usaban los
    // pills sueltos: palette[8]). Fallback al azul que tenían hardcodeado
    // antes de migrar, por si algo lee esto con palette aún vacío.
    readonly property color accent: palette.length > 8 ? palette[8] : "#89B4FA"
    // danger: color de error/alerta, definido una sola vez. La paleta viene
    // del wallpaper y no garantiza un rojo utilizable, así que se mantiene
    // fijo (mismo valor que ya estaba hardcodeado en varios widgets).
    readonly property color danger: "#F38BA8"
    // accentText: texto legible sobre un fondo accent/danger sólido.
    // (Nombrada así y no "onAccent" a propósito: QML trata cualquier
    // identificador que empieza con "on" + mayúscula como handler de señal,
    // "onAccent" rompía el parser con "Cannot assign a value to a signal".)
    readonly property color accentText: "#1E1E2E"

    // ── Texto legible sobre un fondo, siempre desde la paleta ──────
    // Devuelve el color de palette con mejor contraste WCAG contra bg.
    // Si ninguno alcanza minRatio (AA 4.5:1 por defecto), mezcla el mejor
    // candidato hacia blanco/negro solo lo mínimo necesario
    // (OrderColors.adjustForContrast), para conservar el tono del
    // wallpaper; blanco/negro puros solo si la paleta está vacía.
    function readableOn(bg, pal, minRatio) {
        minRatio = minRatio || 4.5
        if (!pal || pal.length === 0)
            return OrderColors.getReadableTextColor(bg)

        var best = pal[0]
        var bestRatio = OrderColors.getContrastRatio(best, bg)
        for (var i = 1; i < pal.length; i++) {
            var r = OrderColors.getContrastRatio(pal[i], bg)
            if (r > bestRatio) {
                bestRatio = r
                best = pal[i]
                console.log(best)
            }
        }
        if (bestRatio >= minRatio)
            return best
        return OrderColors.adjustForContrast(best, bg, minRatio)
    }

    // Mide el contraste del color que el componente ya usa contra su
    // fondo real: si es legible (≥ minRatio) lo devuelve intacto — cero
    // cambio visual — y si no alcanza, el sustituto es el AJUSTE MÍNIMO
    // del propio fg que llega al ratio (mezcla hacia blanco/negro por
    // bisección), no otro color de la paleta: así el reemplazo conserva
    // el tono del original y el cambio visual es el menor posible.
    function ensureReadable(fg, bg, minRatio) {
        // WCAG AA (4.5:1) reducido un 20%: interviene solo en casos
        // realmente pobres y conserva más seguido el diseño original.
        minRatio = minRatio || 2.5
        if (OrderColors.getContrastRatio(fg, bg) >= minRatio)
            return fg
        return OrderColors.adjustForContrast(fg, bg, minRatio)
    }

    // ── Lectura del wallpaper desde disco ─────────────────────────

    Process {
        id: getWallpaper
        running: false
        // Invocamos a sh para que entienda el pipe '|'
        command: [ "sh", "-c", "awww query | awk -F'image: ' '{print $2}' | head -n1" ]
        
        stdout: StdioCollector {
            // Usamos el argumento directamente en lugar de 'this'
            onStreamFinished: (output) => {
                const raw = this.text.trim()
                if (raw === "") return
                
                // Aplicamos la misma lógica de "file://" que en FileView
                const resolved = raw.startsWith("/") ? "file://" + raw : raw
                
                if (resolved !== colors.wallpaperPath) {
                    colors.ready = false
                    colors.wallpaperPath = resolved
                    // console.log("Wallpaper via swww:", colors.wallpaperPath)
                }
            }    
        }
    }

    FileView {
        id: file
        path: "/tmp/actual_wallpaper.txt"
        watchChanges: true
        // En el primer arranque tras un reboot el archivo aún no existe; el caso
        // ya está cubierto por onLoadFailed (fallback a `awww query`), así que
        // el WARN de FileView en el log solo era ruido.
        printErrors: false

        onFileChanged: file.reload()

        onTextChanged: {
            const raw = file.text().trim()
            if (raw === "") return

            const resolved = raw.startsWith("/") ? "file://" + raw : raw

            // Solo actuar si cambió realmente
            if (resolved === colors.wallpaperPath) return

            // ❶ Bajar el semáforo mientras se reprocesa
            colors.ready = false
            colors.wallpaperPath = resolved
        }
        
        onLoadFailed: {
            getWallpaper.running = true
        }    
    }

    // ── Quantizador de color ───────────────────────────────────────
    ColorQuantizer {
        id: colorQuantizer
        source: colors.wallpaperPath
        depth: 3
        rescaleSize: 512

        // ❷ Subir el semáforo cuando los colores estén disponibles
        onColorsChanged: {
            if (!colorQuantizer.colors || colorQuantizer.colors.length === 0)
                return

            colors.palette = OrderColors.extrapolateAndSort(
                colorQuantizer.colors, 10
            )
            colors.ready = true
        }
    }
}
