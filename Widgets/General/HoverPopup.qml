/**
 * HoverPopup.qml — Popup modular anclado a un Item, para Quickshell
 *
 * La apertura la controla el DUEÑO escribiendo `show` — este módulo no
 * engancha hover ni click por su cuenta (Battery abre por hover, Pipewire
 * por click).
 *
 * USO:
 *   WrapperMouseArea {
 *       id: main
 *       // El HoverPopup NO debe quedar como `child` del wrapper: fija
 *       // `child:` explícito o MarginWrapperManager lo tomará por contenido.
 *       child: text
 *       hoverEnabled: true
 *       onEntered: pop.show = true
 *       onExited:  pop.show = false
 *
 *       Text { id: text; text: "hola" }
 *
 *       HoverPopup {
 *           id: pop
 *           triggerItem: main          // Item al que se ancla. OBLIGATORIO.
 *
 *           popupWidth: 160
 *           popupHeight: 80
 *           offsetX: 0                 // Desplazamiento extra sobre el ancla
 *           offsetY: 0
 *
 *           popupContent: Rectangle { anchors.fill: parent }
 *       }
 *   }
 */

import QtQuick
import Quickshell
import qs.Commons

Item {
    id: hoverPopup

    // ─── API pública ──────────────────────────────────────────────────────────

    /// Item al que se ancla el popup. OBLIGATORIO.
    required property Item triggerItem

    /// Componente QML con el contenido interno del popup. Se instancia solo
    /// mientras el popup está abierto (o cerrándose).
    property Component popupContent: null

    /// Dimensiones del popup
    property real popupWidth: 160
    property real popupHeight: 80

    /// Desplazamientos extra sobre la posición calculada
    property real offsetX: 0
    property real offsetY: 0

    /// Animación de fade al abrir/cerrar (true por defecto)
    property bool animated: true

    /// Abre/cierra el popup. La escribe el dueño; ver el ejemplo de arriba.
    property bool show: false

    // ─── Ventana popup ───────────────────────────────────────────────────────

    PopupWindow {
        id: popup

        // anchor.item deja el seguimiento del Item en manos de Quickshell (mismo
        // patrón que Widgets/General/PanelPopup.qml). El rect es RELATIVO al
        // item, así que este binding equivale al viejo
        // mapToItem(null, offsetX, triggerItem.height + offsetY) — pero, al ser
        // un binding y no una función imperativa, también se refresca cuando
        // cambian los offsets o el tamaño del popup (popupHeight de Battery es
        // un binding vivo sobre los datos de UPower).
        anchor.item: hoverPopup.triggerItem
        anchor.rect: Qt.rect(hoverPopup.offsetX,
                             hoverPopup.triggerItem.height + hoverPopup.offsetY,
                             hoverPopup.popupWidth,
                             hoverPopup.popupHeight)
        // edges/gravity quedan en su default (Top|Left / Bottom|Right): el popup
        // nace en la esquina superior izquierda del rect y crece abajo-derecha.
        // SlideX evita que se corte en el borde de pantalla — los callers anclan
        // con offsetX negativo para centrarse sobre el widget.
        anchor.adjustment: PopupAdjustment.SlideX

        implicitWidth:  hoverPopup.popupWidth
        implicitHeight: hoverPopup.popupHeight

        // La ventana debe estar visible para que la opacidad funcione
        visible: hoverPopup.show || (hoverPopup.animated && fadeAnim.running)

        color: "transparent"

        // ── Contenedor visual con fade ─────────────────────────────────────

        Item {
            id: contentRoot
            anchors.fill: parent

            opacity: hoverPopup.show ? 1.0 : 0.0

            Behavior on opacity {
                enabled: hoverPopup.animated
                NumberAnimation {
                    id: fadeAnim
                    duration: Config.anim.panel
                    easing.type: Config.easingOf(Config.anim.standard)
                }
            }

            Loader {
                anchors.fill: parent
                // Sin esto el árbol de popupContent vive desde el arranque en
                // cada monitor, aunque nunca se abra el popup.
                active: popup.visible
                sourceComponent: hoverPopup.popupContent
            }
        }
    }
}
