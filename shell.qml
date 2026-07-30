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

    // Togglea la barra lateral (Obsidian / Claude Code). El lado Hyprland es
    // `bind = $mainMod, A, global, quickshell:sidebarToggle`.
    GlobalShortcut {
        appid: "quickshell"
        name: "sidebarToggle"
        description: "Toggle de la barra lateral"
        onPressed: SidebarState.toggle()
    }

    // Togglea el patchbay de PipeWire. El lado Hyprland es
    // `bind = $mainMod, P, global, quickshell:patchbayToggle`.
    GlobalShortcut {
        appid: "quickshell"
        name: "patchbayToggle"
        description: "Toggle del patchbay de PipeWire"
        onPressed: PopupState.toggle("patchbay")
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
                Patchbay {}
                NotificationToast {}
                Sidebar {}
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
