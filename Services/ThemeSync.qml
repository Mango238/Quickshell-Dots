pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

/**
 * ThemeSync.qml — Propaga Colors.palette (la paleta derivada del wallpaper)
 * fuera de Quickshell, hacia:
 *
 *   - kitty:    ~/.config/kitty/colors-quickshell.conf   (include en kitty.conf;
 *               el watcher de kitty recarga en vivo las ventanas abiertas)
 *   - Hyprland: ~/.config/hypr/colors-quickshell.conf    (source en hyprland.conf;
 *               Hyprland recarga solo al cambiar un archivo sourced)
 *   - starship: renderiza ~/.config/starship/starship.template.toml →
 *               starship.toml reemplazando los tokens TSCFW10..15 (el sistema
 *               de templates que ya usaba el pipeline Python retirado);
 *               starship relee su config en cada prompt.
 *
 * Los singletons de Quickshell son perezosos: este se activa con la
 * referencia `property var _themeSync: ThemeSync` de shell.qml.
 *
 * Decisión del usuario: NUNCA emitir `background` para kitty — conserva su
 * negro translúcido (background #000000 + background_opacity 0.2).
 */
QtObject {
    id: root

    readonly property string _home: Quickshell.env("HOME")

    /// Token TSCFW → índice de Colors.palette (rampa oscuro→claro).
    /// Calibrado contra los valores históricos del pipeline de templates:
    /// TSCFW14/13/12 son los tonos medios que usaba el borde activo de
    /// Hyprland (rgba(TSCFW14ee) rgba(TSCFW13aa) rgba(TSCFW12aa)).
    readonly property var tokenMap: ({
        "TSCFW10": 2,
        "TSCFW11": 3,
        "TSCFW12": 4,
        "TSCFW13": 5,
        "TSCFW14": 6,
        "TSCFW15": 8
    })

    readonly property string header:
        "# Generado por Quickshell (Services/ThemeSync.qml) desde el wallpaper actual.\n" +
        "# NO editar a mano: se reescribe en cada cambio de wallpaper.\n"

    function _hex(i) { return String(Colors.palette[i]) }        // "#rrggbb"
    function _raw(i) { return String(Colors.palette[i]).slice(1) } // "rrggbb"

    // ─── Generadores de contenido ───────────────────────────────────────────

    // Decisión del usuario (2026-07-17): el texto tipeado y los outputs usan
    // los colores default (su foreground inline de kitty.conf y los ANSI
    // estándar) — NO se emiten `foreground` ni `color0..15`. De la paleta
    // del wallpaper solo se tematizan cursor y selección. Tampoco
    // `background` (negro translúcido del usuario).
    function _kittyContent() {
        return root.header
            + "cursor " + String(Colors.accent) + "\n"
            + "cursor_text_color " + _hex(0) + "\n"
            + "selection_background " + String(Colors.accent) + "\n"
            + "selection_foreground " + _hex(0) + "\n"
    }

    function _hyprContent() {
        var out = root.header
        for (var i = 0; i < 10; i++)
            out += "$qsPalette" + i + " = rgb(" + _raw(i) + ")\n"
        out += "$qsAccent = rgb(" + String(Colors.accent).slice(1) + ")\n"
        // Mismos stops que el borde activo histórico (TSCFW14ee/13aa/12aa)
        out += "$qsBorderActive1 = rgba(" + _raw(6) + "ee)\n"
        out += "$qsBorderActive2 = rgba(" + _raw(5) + "aa)\n"
        out += "$qsBorderActive3 = rgba(" + _raw(4) + "aa)\n"
        return out
    }

    function _starshipContent(templateText) {
        var out = templateText
        for (var tok in root.tokenMap)
            out = out.split(tok).join(_hex(root.tokenMap[tok]))
        return "# Generado por Quickshell (ThemeSync) desde starship.template.toml.\n"
            + "# NO editar a mano: editá el template; esto se reescribe con el wallpaper.\n"
            + out
    }

    // ─── Archivos ───────────────────────────────────────────────────────────

    readonly property FileView kittyFile: FileView {
        path: root._home + "/.config/kitty/colors-quickshell.conf"
        printErrors: false
        // El watcher de kitty NO recarga archivos include (verificado con
        // centinela); SIGUSR1 sí fuerza la recarga de config en todas las
        // instancias. En onSaved (no tras setText) porque la escritura del
        // FileView es asíncrona: señalizar antes recargaría el archivo viejo.
        onSaved: Quickshell.execDetached(["pkill", "-USR1", "-x", "kitty"])
        onSaveFailed: (error) => console.warn("ThemeSync: fallo escribiendo colores de kitty:", error)
    }

    readonly property FileView hyprFile: FileView {
        path: root._home + "/.config/hypr/colors-quickshell.conf"
        printErrors: false
        onSaveFailed: (error) => console.warn("ThemeSync: fallo escribiendo colores de Hyprland:", error)
    }

    // El template se observa: editarlo re-renderiza starship.toml al vuelo.
    readonly property FileView starshipTemplate: FileView {
        path: root._home + "/.config/starship/starship.template.toml"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._scheduleWrite()
        onLoadFailed: (error) => console.warn("ThemeSync: no se pudo leer starship.template.toml:", error)
    }

    readonly property FileView starshipOut: FileView {
        path: root._home + "/.config/starship/starship.toml"
        printErrors: false
        onSaveFailed: (error) => console.warn("ThemeSync: fallo escribiendo starship.toml:", error)
    }

    // ─── Disparo ────────────────────────────────────────────────────────────

    // Coalesce: un cambio de wallpaper baja ready y repuebla palette; un solo
    // write al final.
    readonly property Timer _debounce: Timer {
        interval: 300
        onTriggered: root._writeAll()
    }

    function _scheduleWrite() { root._debounce.restart() }

    readonly property Connections _colorsWatch: Connections {
        target: Colors
        function onPaletteChanged() { root._scheduleWrite() }
        function onReadyChanged() { if (Colors.ready) root._scheduleWrite() }
    }

    function _writeAll() {
        if (!Colors.ready || !Colors.palette || Colors.palette.length < 10) return
        kittyFile.setText(_kittyContent())
        hyprFile.setText(_hyprContent())
        var tpl = starshipTemplate.text()
        // Guard: si el template no cargó aún (o no tiene tokens), no pisar
        // starship.toml con algo vacío; onLoaded re-agenda cuando esté.
        if (tpl && tpl.indexOf("TSCFW") !== -1)
            starshipOut.setText(_starshipContent(tpl))
    }

    Component.onCompleted: _scheduleWrite()
}
