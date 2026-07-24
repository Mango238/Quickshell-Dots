import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.Modules
import qs.Commons
import qs.Services

ShellRoot {

    // WIN+Q — togglea el selector de wallpapers. El lado Hyprland es
    // `bind = $mainMod, Q, global, quickshell:wallpaperToggle` en hyprland.conf.
    GlobalShortcut {
        appid: "quickshell"
        name: "wallpaperToggle"
        description: "Toggle del selector de wallpapers"
        onPressed: PopupState.toggle("wallpaper")
    }

    // Activa el singleton ThemeSync (perezoso): propaga Colors.palette a
    // kitty/Hyprland/starship en cada cambio de wallpaper.
    property var _themeSync: ThemeSync

    // ── UI bloqueada hasta que la paleta esté lista ─────────────

    Loader {
        id:     shellLoader
        active: Colors.ready

        sourceComponent: Component {
            Item {
                Bar          {}
                ClockWidget  {}
                Equalizer {}
                NotificationToast {}
            }
        }
    }

    Loader {
        id: eqBootstrapLoader
        active: false
        source: "Services/EqBootstrap.qml"
    }

    Timer {
        interval: 300
        repeat: false
        running: true
        onTriggered: eqBootstrapLoader.active = true
    }
}
