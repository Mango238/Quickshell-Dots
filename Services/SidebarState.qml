pragma Singleton
import QtQuick
import Quickshell.Hyprland

// Estado compartido de la barra lateral. Espejo de PopupState.qml, pero el
// sidebar NO es mutuamente exclusivo con los popups de la barra: mantiene su
// propia bandera `open` y su vista activa mientras está abierto. `screenName`
// restringe la instancia visible al monitor donde se abrió (una PanelWindow
// por monitor vía Variants, igual que Bar.qml).
QtObject {
    property bool open: false
    // Vista mostrada dentro del sidebar: "obsidian" | "claude" | "config".
    property string activeView: "obsidian"
    // Conector del monitor donde se abrió (p. ej. "eDP-1"). "" = sin
    // restricción (fallback si no hay IPC de Hyprland).
    property string screenName: ""

    function _focusedName() {
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    }

    function toggle() {
        open = !open
        screenName = open ? _focusedName() : ""
    }

    function show(view) {
        activeView = view
        open = true
        screenName = _focusedName()
    }

    function close() {
        open = false
    }

    function isOpenOn(screen) {
        return open && (screenName === "" || !screen || screenName === screen.name)
    }
}
