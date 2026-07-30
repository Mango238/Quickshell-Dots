pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Config.qml — Config de usuario en Config/config.json, con recarga y
 * escritura en vivo (JsonAdapter). Si el archivo no existe o está corrupto,
 * cada property cae a su default QML — el mismo valor que el repo ya usaba
 * antes de esta config: comportamiento idéntico a "hoy" sin archivo.
 *
 * Regla para consumidores: bindear y escribir SIEMPRE directo a Config.*
 * (p. ej. Config.lock.hidePassword), nunca a una property espejo local —
 * eso rompe la recarga en vivo y el archivo deja de mandar.
 */
Singleton {
    id: root

    readonly property string _home: Quickshell.env("HOME")

    /// Valores por defecto de lo que NO describe a la máquina ni al usuario.
    /// Es la única copia: las properties del adapter se inicializan desde acá,
    /// y resetDefaults() reasigna desde acá — no hay dos listas que se separen.
    /// Fuera a propósito: user.*, wallpaper.*, players, obsidian.*, themeSync.*
    /// y power.* (rutas, comandos y datos personales de esta instalación).
    readonly property var defaults: ({
        font: "JetBrainsMono Nerd Font",
        lock: { hidePassword: false, revealDuration: 300 },
        anim: { instant: 120, base: 200, panel: 300, slow: 600, ambient: 1000,
                standard: "OutCubic", emphasized: "OutBack",
                decelerate: "OutExpo", exit: "InCubic" }
    })

    /// Devuelve font, lock.* y anim.* a los valores de arriba.
    ///
    /// Escribir 12 properties de corrido NO funciona con el ciclo normal
    /// (write → writeAdapter → fileChanged → reload): cada write dispara su
    /// propio guardado asíncrono, y los recargados intermedios revierten las
    /// asignaciones que aún no llegaron al disco — medido, se perdían entre 1
    /// y 2 de cada 5. Por eso la ráfaga se hace con el guardado y el watch en
    /// pausa, y termina en UN solo write. Un cambio suelto —lo que hace el
    /// resto del panel— no necesita nada de esto.
    property bool _bulk: false

    function resetDefaults() {
        root._bulk = true
        view.watchChanges = false
        root.font = root.defaults.font
        for (const k in root.defaults.lock)
            root.lock[k] = root.defaults.lock[k]
        for (const k in root.defaults.anim)
            root.anim[k] = root.defaults.anim[k]
        root._bulk = false
        view.writeAdapter()
        rewatch.restart()
    }

    /// Reanuda el watch cuando el fileChanged del write final ya pasó.
    property Timer _rewatch: Timer {
        id: rewatch
        interval: 500
        onTriggered: view.watchChanges = true
    }

    /// Easing.OutCubic no es serializable a JSON: se guarda el nombre como
    /// string y se mapea acá a la constante real de Qt Quick.
    function easingOf(name) {
        switch (name) {
        case "OutCubic": return Easing.OutCubic
        case "OutBack":  return Easing.OutBack
        case "OutExpo":  return Easing.OutExpo
        case "InCubic":  return Easing.InCubic
        default:         return Easing.OutCubic
        }
    }

    property alias font: adapter.font
    property alias user: adapter.user
    property alias wallpaper: adapter.wallpaper
    property alias players: adapter.players
    property alias obsidian: adapter.obsidian
    property alias themeSync: adapter.themeSync
    property alias power: adapter.power
    property alias lock: adapter.lock
    property alias anim: adapter.anim

    /// El directorio Config/ no lo trackea git (solo contiene el config.json
    /// ignorado), así que en un clon nuevo no existe. FileView no lo crea.
    Component.onCompleted: Quickshell.execDetached(
        ["mkdir", "-p", root._home + "/.config/quickshell/Config"])

    /// Una sola siembra por proceso: sin esto el archivo queda invisible.
    /// JsonAdapter escribe solo cuando una property CAMBIA, y al arrancar
    /// ninguna cambia — un config.json ausente o a medias se quedaba así,
    /// sin nada que leer ni editar. Escribirlo una vez tras la carga lo deja
    /// expandido con el esquema completo y rellena las claves que falten.
    /// El flag corta el loop writeAdapter → fileChanged → reload → onLoaded.
    property bool _seeded: false

    function _seed(view) {
        if (root._seeded) return
        root._seeded = true
        view.writeAdapter()
    }

    FileView {
        id: view
        path: root._home + "/.config/quickshell/Config/config.json"
        watchChanges: true
        printErrors: false          // primer arranque: el archivo no existe
        onFileChanged: reload()
        onAdapterUpdated: if (!root._bulk) writeAdapter()
        onLoaded: root._seed(view)
        onLoadFailed: root._seed(view)   // no existía: crearlo con los defaults

        JsonAdapter {
            id: adapter

            property string font: "JetBrainsMono Nerd Font"

            property JsonObject user: JsonObject {
                property string displayName: ""
                property string avatar: ""
            }

            property JsonObject wallpaper: JsonObject {
                property string dir: root._home + "/Imágenes/archlinux-favorite-wallpapers/"
                property string backend: "awww"
                property string stateFile: "/tmp/actual_wallpaper.txt"
                property string wallAnim: "wave"

            }

            property list<string> players: ["Spotify", "Spotifyd"]

            property JsonObject obsidian: JsonObject {
                property string configPath: root._home + "/.config/obsidian/obsidian.json"
            }

            property JsonObject themeSync: JsonObject {
                property string kitty: root._home + "/.config/kitty/colors-quickshell.conf"
                property string hyprland: root._home + "/.config/hypr/colors-quickshell.lua"
                property string starship: root._home + "/.config/starship/starship.toml"
                property list<string> reloadCmd: ["pkill", "-USR1", "-x", "kitty"]
            }

            property JsonObject power: JsonObject {
                property list<string> lock: ["loginctl", "lock-session"]
                property list<string> poweroff: ["systemctl", "poweroff"]
                property list<string> reboot: ["systemctl", "reboot"]
                property list<string> suspend: ["systemctl", "suspend"]
                /// Config Lua de Hyprland: `dispatch` toma una expresión Lua.
                property list<string> logout: ["hyprctl", "dispatch", "hl.dsp.exit()"]
            }

            property JsonObject lock: JsonObject {
                property bool hidePassword: false
                property int revealDuration: 300
            }

            property JsonObject anim: JsonObject {
                property int instant: 120
                property int base: 200
                property int panel: 300
                property int slow: 600
                property int ambient: 1000
                property string standard: "OutCubic"
                property string emphasized: "OutBack"
                property string decelerate: "OutExpo"
                property string exit: "InCubic"
            }
        }
    }
}
