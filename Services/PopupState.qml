pragma Singleton
import QtQuick
import Quickshell.Hyprland

QtObject {
    property string active: ""
    // Conector del monitor donde se abrió el popup activo (p. ej. "eDP-1").
    // Cada barra (una por monitor vía Variants) muestra solo el popup de su
    // propio monitor — sin esto, el popup aparecía duplicado en todos, y en
    // los que tienen grabKeyboardFocus los dos HyprlandFocusGrab se pisaban
    // entre sí. "" = sin restricción (fallback si no hay IPC de Hyprland).
    property string screenName: ""
    property bool open: false

    function toggle(name) {
        active = (active === name) ? "" : name
        screenName = (active !== "" && Hyprland.focusedMonitor)
                   ? Hyprland.focusedMonitor.name : ""
    }

    function isOpen(name) {
        return active === name
    }

    // Como isOpen, pero restringido al monitor que abrió el popup: para los
    // bindings `show` de los PanelPopup de Bar.qml, que existen por monitor.
    function isOpenOn(name, screen) {
        return active === name
            && (screenName === "" || !screen || screenName === screen.name)
    }
}
