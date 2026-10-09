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

    // Muesca de la barra sobre el popup abierto: qué popup la reclamó, el
    // item de la barra al que se ancla y el centro (en coords de notchItem).
    property QtObject notchOwner: null
    property Item notchItem: null
    property real notchX: 0
    // Tamaño compartido: la barra hace el hueco y el PanelPopup lo rellena
    // con su propia forma, así que ambos deben usar los mismos valores.
    readonly property real notchHalfWidth: 7
    readonly property real notchDepth: 5
    function setNotch(owner, item, x) { notchOwner = owner; notchItem = item; notchX = x }
    // Compara el dueño: al pasar de un popup a otro sobre el mismo item, el
    // cierre del anterior no borra la muesca del nuevo.
    function clearNotch(owner) { if (notchOwner === owner) { notchOwner = null; notchItem = null } }

    function toggle(name) {
        active = (active === name) ? "" : name
        screenName = (active !== "" && Hyprland.focusedMonitor)
                   ? Hyprland.focusedMonitor.name : ""
    }

    function close() {
        active = ""
        screenName = ""
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
